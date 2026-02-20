//! This module defines some database functionality for the community site.

use std::time::Duration;

use anyhow::Result;
use async_trait::async_trait;
use cached::proc_macro::cached;
use deadpool_postgres::Client;
use tokio_postgres::types::Json;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::community,
    types::{
        event::{EventKind, EventSummary},
        group::GroupSummary,
    },
};

/// Database trait defining all data access operations for the community site.
#[async_trait]
pub(crate) trait DBCommunity {
    /// Resolves a community ID from the provided community name.
    async fn get_community_id_by_name(&self, name: &str) -> Result<Option<Uuid>>;

    /// Resolves a community name from the provided community ID.
    async fn get_community_name_by_id(&self, community_id: Uuid) -> Result<Option<String>>;

    /// Retrieves the most recently added groups in the community.
    async fn get_community_recently_added_groups(&self, community_id: Uuid) -> Result<Vec<GroupSummary>>;

    /// Retrieves statistical data for the community page.
    async fn get_community_site_stats(&self, community_id: Uuid) -> Result<community::Stats>;

    /// Retrieves upcoming events for the community.
    async fn get_community_upcoming_events(
        &self,
        community_id: Uuid,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>>;
}

#[async_trait]
impl DBCommunity for PgDB {
    /// [`DB::get_community_id_by_name`]
    #[instrument(skip(self), err)]
    async fn get_community_id_by_name(&self, name: &str) -> Result<Option<Uuid>> {
        #[cached(
            time = 86400,
            key = "String",
            convert = r#"{ String::from(name) }"#,
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client, name: &str) -> Result<Option<Uuid>> {
            trace!("db: get community id by name");

            let community_id = db
                .query_opt("select get_community_id_by_name($1::text)", &[&name])
                .await?
                .and_then(|row| row.get(0));

            Ok(community_id)
        }

        if name.is_empty() {
            return Ok(None);
        }
        let db = self.pool.get().await?;
        inner(db, name).await
    }

    /// [`DB::get_community_name_by_id`]
    #[instrument(skip(self), err)]
    async fn get_community_name_by_id(&self, community_id: Uuid) -> Result<Option<String>> {
        #[cached(
            time = 86400,
            key = "Uuid",
            convert = r#"{ community_id }"#,
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client, community_id: Uuid) -> Result<Option<String>> {
            trace!("db: get community name by id");

            let name = db
                .query_opt("select get_community_name_by_id($1::uuid)", &[&community_id])
                .await?
                .and_then(|row| row.get(0));

            Ok(name)
        }

        let db = self.pool.get().await?;
        inner(db, community_id).await
    }

    /// [`DB::get_community_recently_added_groups`]
    #[instrument(skip(self), err)]
    async fn get_community_recently_added_groups(&self, community_id: Uuid) -> Result<Vec<GroupSummary>> {
        trace!("db: get community recently added groups");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_community_recently_added_groups($1::uuid)",
                &[&community_id],
            )
            .await?;
        let groups = row.try_get::<_, Json<Vec<GroupSummary>>>(0)?.0;

        Ok(groups)
    }

    /// [`DB::get_community_site_stats`]
    #[instrument(skip(self), err)]
    async fn get_community_site_stats(&self, community_id: Uuid) -> Result<community::Stats> {
        trace!("db: get community site stats");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_community_site_stats($1::uuid)", &[&community_id])
            .await?;
        let stats = row.try_get::<_, Json<community::Stats>>(0)?.0;

        Ok(stats)
    }

    /// [`DB::get_community_upcoming_events`]
    #[instrument(skip(self), err)]
    async fn get_community_upcoming_events(
        &self,
        community_id: Uuid,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>> {
        trace!("db: get community upcoming events");

        let event_kinds = event_kinds.into_iter().map(|k| k.to_string()).collect::<Vec<_>>();
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_community_upcoming_events($1::uuid, $2::text[])",
                &[&community_id, &event_kinds],
            )
            .await?;
        let events = row.try_get::<_, Json<Vec<EventSummary>>>(0)?.0;

        Ok(events)
    }
}
