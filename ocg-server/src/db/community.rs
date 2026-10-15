//! This module defines some database functionality for the community site.

use anyhow::Result;
use async_trait::async_trait;
use cached::cached;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::{PgClient, PgExecutor, cache_probe},
    types::{
        community::CommunityStats,
        event::{EventKind, EventSummary},
        group::GroupSummary,
    },
};

/// Database trait defining all data access operations for the community site.
#[async_trait]
pub(crate) trait DBCommunity {
    /// Resolves a community ID from the provided community name.
    ///
    /// Cached for up to one day per process.
    async fn get_community_id_by_name(&self, name: &str) -> Result<Option<Uuid>>;

    /// Retrieves the most recently added groups in the community.
    async fn get_community_recently_added_groups(
        &self,
        community_id: Uuid,
    ) -> Result<Vec<GroupSummary>>;

    /// Retrieves statistical data for the community page.
    ///
    /// Cached for up to one hour per process. Aggregates mutable data; see
    /// "Cached reads and transactions" in `docs/backend.md` before calling it
    /// from a transaction.
    async fn get_community_site_stats(&self, community_id: Uuid) -> Result<CommunityStats>;

    /// Retrieves upcoming events for the community.
    async fn get_community_upcoming_events(
        &self,
        community_id: Uuid,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>>;
}

#[async_trait]
impl<T> DBCommunity for T
where
    T: PgExecutor + Send + Sync,
{
    /// [`DB::get_community_id_by_name`]
    #[instrument(skip(self), err)]
    async fn get_community_id_by_name(&self, name: &str) -> Result<Option<Uuid>> {
        #[cached(
            ttl = 86400,
            key = "String",
            convert = r#"{ String::from(name) }"#,
            sync_writes = "by_key"
        )]
        async fn inner(db: &PgClient<'_>, name: &str) -> Result<Option<Uuid>> {
            db.fetch_scalar_opt("select get_community_id_by_name($1::text)", &[&name])
                .await
        }

        if name.is_empty() {
            return Ok(None);
        }

        // Serve a fresh cached value without checking out a client
        if let Some(community_id) = cache_probe(&INNER.0, name).await {
            return Ok(community_id);
        }

        // Check out the client before the cached fill takes its key lock
        let db = self.client().await?;
        inner(&db, name).await
    }

    /// [`DB::get_community_recently_added_groups`]
    #[instrument(skip(self), err)]
    async fn get_community_recently_added_groups(
        &self,
        community_id: Uuid,
    ) -> Result<Vec<GroupSummary>> {
        self.fetch_json_one(
            "select get_community_recently_added_groups($1::uuid)",
            &[&community_id],
        )
        .await
    }

    /// [`DB::get_community_site_stats`]
    #[instrument(skip(self), err)]
    async fn get_community_site_stats(&self, community_id: Uuid) -> Result<CommunityStats> {
        #[cached(
            ttl = 3600,
            key = "Uuid",
            convert = r#"{ community_id }"#,
            sync_writes = "by_key"
        )]
        async fn inner(db: &PgClient<'_>, community_id: Uuid) -> Result<CommunityStats> {
            db.fetch_json_one(
                "select get_community_site_stats($1::uuid)",
                &[&community_id],
            )
            .await
        }

        // Serve a fresh cached value without checking out a client
        if let Some(stats) = cache_probe(&INNER.0, &community_id).await {
            return Ok(stats);
        }

        // Check out the client before the cached fill takes its key lock
        let db = self.client().await?;
        inner(&db, community_id).await
    }

    /// [`DB::get_community_upcoming_events`]
    #[instrument(skip(self), err)]
    async fn get_community_upcoming_events(
        &self,
        community_id: Uuid,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>> {
        let event_kinds = event_kinds.into_iter().map(|k| k.to_string()).collect::<Vec<_>>();
        self.fetch_json_one(
            "select get_community_upcoming_events($1::uuid, $2::text[])",
            &[&community_id, &event_kinds],
        )
        .await
    }
}
