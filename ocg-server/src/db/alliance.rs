//! This module defines some database functionality for the alliance site.

use anyhow::Result;
use async_trait::async_trait;
use cached::proc_macro::cached;
use deadpool_postgres::Client;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::alliance,
    types::{
        event::{EventKind, EventSummary},
        group::GroupSummary,
    },
};

/// Database trait defining all data access operations for the alliance site.
#[async_trait]
pub(crate) trait DBAlliance {
    /// Resolves a alliance ID from the provided alliance name.
    async fn get_alliance_id_by_name(&self, name: &str) -> Result<Option<Uuid>>;

    /// Resolves a alliance name from the provided alliance ID.
    async fn get_alliance_name_by_id(&self, alliance_id: Uuid) -> Result<Option<String>>;

    /// Retrieves the most recently added groups in the alliance.
    async fn get_alliance_recently_added_groups(
        &self,
        alliance_id: Uuid,
    ) -> Result<Vec<GroupSummary>>;

    /// Retrieves statistical data for the alliance page.
    async fn get_alliance_site_stats(&self, alliance_id: Uuid) -> Result<alliance::Stats>;

    /// Retrieves upcoming events for the alliance.
    async fn get_alliance_upcoming_events(
        &self,
        alliance_id: Uuid,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>>;
}

#[async_trait]
impl DBAlliance for PgDB {
    /// [`DB::get_alliance_id_by_name`]
    #[instrument(skip(self), err)]
    async fn get_alliance_id_by_name(&self, name: &str) -> Result<Option<Uuid>> {
        #[cached(
            time = 86400,
            key = "String",
            convert = r#"{ String::from(name) }"#,
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client, name: &str) -> Result<Option<Uuid>> {
            let alliance_id = db
                .query_opt("select get_alliance_id_by_name($1::text)", &[&name])
                .await?
                .and_then(|row| row.get(0));

            Ok(alliance_id)
        }

        if name.is_empty() {
            return Ok(None);
        }
        let db = self.pool.get().await?;
        inner(db, name).await
    }

    /// [`DB::get_alliance_name_by_id`]
    #[instrument(skip(self), err)]
    async fn get_alliance_name_by_id(&self, alliance_id: Uuid) -> Result<Option<String>> {
        #[cached(
            time = 86400,
            key = "Uuid",
            convert = r#"{ alliance_id }"#,
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client, alliance_id: Uuid) -> Result<Option<String>> {
            let name = db
                .query_opt(
                    "select get_alliance_name_by_id($1::uuid)",
                    &[&alliance_id],
                )
                .await?
                .and_then(|row| row.get(0));

            Ok(name)
        }

        let db = self.pool.get().await?;
        inner(db, alliance_id).await
    }

    /// [`DB::get_alliance_recently_added_groups`]
    #[instrument(skip(self), err)]
    async fn get_alliance_recently_added_groups(
        &self,
        alliance_id: Uuid,
    ) -> Result<Vec<GroupSummary>> {
        self.fetch_json_one(
            "select get_alliance_recently_added_groups($1::uuid)",
            &[&alliance_id],
        )
        .await
    }

    /// [`DB::get_alliance_site_stats`]
    #[instrument(skip(self), err)]
    async fn get_alliance_site_stats(&self, alliance_id: Uuid) -> Result<alliance::Stats> {
        self.fetch_json_one(
            "select get_alliance_site_stats($1::uuid)",
            &[&alliance_id],
        )
        .await
    }

    /// [`DB::get_alliance_upcoming_events`]
    #[instrument(skip(self), err)]
    async fn get_alliance_upcoming_events(
        &self,
        alliance_id: Uuid,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>> {
        let event_kinds = event_kinds.into_iter().map(|k| k.to_string()).collect::<Vec<_>>();
        self.fetch_json_one(
            "select get_alliance_upcoming_events($1::uuid, $2::text[])",
            &[&alliance_id, &event_kinds],
        )
        .await
    }
}
