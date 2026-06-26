//! This module defines some database functionality for the alliance site.

use anyhow::Result;
use async_trait::async_trait;
use cached::cached;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::{PgClient, PgExecutor},
    templates::alliance::{self, AllianceMembersFilters, AllianceMembersOutput},
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

    /// Checks whether a user belongs to at least one group in the alliance.
    async fn is_alliance_group_member(&self, alliance_id: Uuid, user_id: Uuid) -> Result<bool>;

    /// Lists members across all groups in the alliance.
    async fn list_alliance_members(
        &self,
        alliance_id: Uuid,
        filters: &AllianceMembersFilters,
    ) -> Result<AllianceMembersOutput>;
}

#[async_trait]
impl<T> DBAlliance for T
where
    T: PgExecutor + Send + Sync,
{
    /// [`DB::get_alliance_id_by_name`]
    #[instrument(skip(self), err)]
    async fn get_alliance_id_by_name(&self, name: &str) -> Result<Option<Uuid>> {
        #[cached(
            ttl = 86400,
            key = "String",
            convert = r#"{ String::from(name) }"#,
            sync_writes = "by_key"
        )]
        async fn inner(db: PgClient<'_>, name: &str) -> Result<Option<Uuid>> {
            let alliance_id = db
                .query_opt("select get_alliance_id_by_name($1::text)", &[&name])
                .await?
                .and_then(|row| row.get(0));

            Ok(alliance_id)
        }

        if name.is_empty() {
            return Ok(None);
        }
        let db = self.client().await?;
        inner(db, name).await
    }

    /// [`DB::get_alliance_name_by_id`]
    #[instrument(skip(self), err)]
    async fn get_alliance_name_by_id(&self, alliance_id: Uuid) -> Result<Option<String>> {
        #[cached(
            ttl = 86400,
            key = "Uuid",
            convert = r#"{ alliance_id }"#,
            sync_writes = "by_key"
        )]
        async fn inner(db: PgClient<'_>, alliance_id: Uuid) -> Result<Option<String>> {
            let name = db
                .query_opt("select get_alliance_name_by_id($1::uuid)", &[&alliance_id])
                .await?
                .and_then(|row| row.get(0));

            Ok(name)
        }

        let db = self.client().await?;
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
        self.fetch_json_one("select get_alliance_site_stats($1::uuid)", &[&alliance_id])
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

    /// [`DBAlliance::is_alliance_group_member`]
    #[instrument(skip(self), err)]
    async fn is_alliance_group_member(&self, alliance_id: Uuid, user_id: Uuid) -> Result<bool> {
        self.fetch_scalar_one(
            r#"
            select exists (
                select 1
                from group_member gm
                join "group" g using (group_id)
                where g.alliance_id = $1::uuid
                  and g.active = true
                  and g.deleted = false
                  and gm.user_id = $2::uuid
            );
            "#,
            &[&alliance_id, &user_id],
        )
        .await
    }

    /// [`DBAlliance::list_alliance_members`]
    #[instrument(skip(self, filters), err)]
    async fn list_alliance_members(
        &self,
        alliance_id: Uuid,
        filters: &AllianceMembersFilters,
    ) -> Result<AllianceMembersOutput> {
        self.fetch_json_one(
            "select list_alliance_members($1::uuid, $2::jsonb)",
            &[&alliance_id, &Json(filters)],
        )
        .await
    }
}
