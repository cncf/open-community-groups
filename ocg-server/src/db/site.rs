//! This module defines some database functionality for the global site.

use anyhow::Result;
use async_trait::async_trait;
use cached::cached;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::{PgClient, PgExecutor},
    types::{
        community::CommunitySummary,
        event::{EventKind, EventMinimal, EventSummary},
        group::{GroupMinimal, GroupSummary},
        search::{
            SearchEventsFilters, SearchEventsOutput, SearchGroupsFilters, SearchGroupsOutput,
        },
        site::{
            SiteHomeStats, SiteSettings,
            explore::{Entity, FiltersOptions},
            stats::SiteStats,
        },
    },
};

/// Trait for database operations related to site.
#[async_trait]
pub(crate) trait DBSite {
    /// Retrieves filters options for the explore page. When a `community_name` is
    /// provided, community-specific filters are included. When `entity` is `Events`
    /// and a community name is provided, groups are also included.
    async fn get_filters_options(
        &self,
        community_name: Option<String>,
        entity: Option<Entity>,
    ) -> Result<FiltersOptions>;

    /// Retrieves the summary of an event whose public page is available.
    async fn get_public_event_summary(&self, event_id: Uuid) -> Result<Option<EventSummary>>;

    /// Retrieves the summary of a group whose public page is available.
    async fn get_public_group_summary(&self, group_id: Uuid) -> Result<Option<GroupSummary>>;

    /// Retrieves the site home stats.
    ///
    /// Cached for up to one hour per process. Aggregates mutable data; see
    /// "Cached reads and transactions" in `docs/backend.md` before calling it
    /// from a transaction.
    async fn get_site_home_stats(&self) -> Result<SiteHomeStats>;

    /// Retrieves the most recently added groups across all communities.
    async fn get_site_recently_added_groups(&self) -> Result<Vec<GroupSummary>>;

    /// Retrieves the site settings.
    ///
    /// Cached for up to five minutes per process.
    async fn get_site_settings(&self) -> Result<SiteSettings>;

    /// Retrieves the site stats for the stats page.
    ///
    /// Cached for up to one hour per process. Aggregates mutable data; see
    /// "Cached reads and transactions" in `docs/backend.md` before calling it
    /// from a transaction.
    async fn get_site_stats(&self) -> Result<SiteStats>;

    /// Retrieves upcoming events across all communities.
    async fn get_site_upcoming_events(
        &self,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>>;

    /// Lists all active communities.
    ///
    /// Cached for up to five minutes per process.
    async fn list_communities(&self) -> Result<Vec<CommunitySummary>>;

    /// Searches the events to draw on the explore map or calendar, returning at
    /// most `limit` minimal items together with the uncapped total.
    async fn search_events_minimal(
        &self,
        filters: &SearchEventsFilters,
        limit: usize,
    ) -> Result<SearchEventsOutput<EventMinimal>>;

    /// Searches the groups to draw on the explore map, returning at most
    /// `limit` minimal items together with the uncapped total.
    async fn search_groups_minimal(
        &self,
        filters: &SearchGroupsFilters,
        limit: usize,
    ) -> Result<SearchGroupsOutput<GroupMinimal>>;
}

#[async_trait]
impl<T> DBSite for T
where
    T: PgExecutor + Send + Sync,
{
    #[instrument(skip(self), err)]
    async fn get_filters_options(
        &self,
        community_name: Option<String>,
        entity: Option<Entity>,
    ) -> Result<FiltersOptions> {
        self.fetch_json_one(
            "select get_filters_options($1::text, $2::text)",
            &[&community_name, &entity.map(|e| e.to_string())],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn get_public_event_summary(&self, event_id: Uuid) -> Result<Option<EventSummary>> {
        self.fetch_json_opt("select get_public_event_summary($1::uuid)", &[&event_id])
            .await
    }

    #[instrument(skip(self), err)]
    async fn get_public_group_summary(&self, group_id: Uuid) -> Result<Option<GroupSummary>> {
        self.fetch_json_opt("select get_public_group_summary($1::uuid)", &[&group_id])
            .await
    }

    #[instrument(skip(self), err)]
    async fn get_site_home_stats(&self) -> Result<SiteHomeStats> {
        #[cached(
            ttl = 3600,
            key = "String",
            convert = r#"{ String::from("site_home_stats") }"#,
            sync_writes = "by_key"
        )]
        async fn inner(db: PgClient<'_>) -> Result<SiteHomeStats> {
            let row = db.query_one("select get_site_home_stats()", &[]).await?;
            let stats = row.try_get::<_, Json<SiteHomeStats>>(0)?.0;

            Ok(stats)
        }

        let db = self.client().await?;
        inner(db).await
    }

    #[instrument(skip(self), err)]
    async fn get_site_recently_added_groups(&self) -> Result<Vec<GroupSummary>> {
        self.fetch_json_one("select get_site_recently_added_groups()", &[])
            .await
    }

    #[instrument(skip(self), err)]
    async fn get_site_settings(&self) -> Result<SiteSettings> {
        #[cached(
            ttl = 300,
            key = "String",
            convert = r#"{ String::from("site_settings") }"#,
            sync_writes = "by_key"
        )]
        async fn inner(db: PgClient<'_>) -> Result<SiteSettings> {
            let row = db.query_one("select get_site_settings()", &[]).await?;
            let settings = row.try_get::<_, Json<SiteSettings>>(0)?.0;

            Ok(settings)
        }

        let db = self.client().await?;
        inner(db).await
    }

    #[instrument(skip(self), err)]
    async fn get_site_stats(&self) -> Result<SiteStats> {
        #[cached(
            ttl = 3600,
            key = "String",
            convert = r#"{ String::from("site_stats") }"#,
            sync_writes = "by_key"
        )]
        async fn inner(db: PgClient<'_>) -> Result<SiteStats> {
            let row = db.query_one("select get_site_stats()", &[]).await?;
            let stats = row.try_get::<_, Json<SiteStats>>(0)?.0;

            Ok(stats)
        }

        let db = self.client().await?;
        inner(db).await
    }

    #[instrument(skip(self), err)]
    async fn get_site_upcoming_events(
        &self,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>> {
        let event_kinds = event_kinds.into_iter().map(|k| k.to_string()).collect::<Vec<_>>();
        self.fetch_json_one(
            "select get_site_upcoming_events($1::text[])",
            &[&event_kinds],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn list_communities(&self) -> Result<Vec<CommunitySummary>> {
        #[cached(
            ttl = 300,
            key = "String",
            convert = r#"{ String::from("communities") }"#,
            sync_writes = "by_key"
        )]
        async fn inner(db: PgClient<'_>) -> Result<Vec<CommunitySummary>> {
            let row = db.query_one("select list_communities();", &[]).await?;
            let communities = row.try_get::<_, Json<Vec<CommunitySummary>>>(0)?.0;

            Ok(communities)
        }

        let db = self.client().await?;
        inner(db).await
    }

    #[instrument(skip(self, filters), err)]
    async fn search_events_minimal(
        &self,
        filters: &SearchEventsFilters,
        limit: usize,
    ) -> Result<SearchEventsOutput<EventMinimal>> {
        let limit = i32::try_from(limit)?;
        self.fetch_json_one(
            "select search_events_minimal($1::jsonb, $2::int)",
            &[&Json(filters), &limit],
        )
        .await
    }

    #[instrument(skip(self, filters), err)]
    async fn search_groups_minimal(
        &self,
        filters: &SearchGroupsFilters,
        limit: usize,
    ) -> Result<SearchGroupsOutput<GroupMinimal>> {
        let limit = i32::try_from(limit)?;
        self.fetch_json_one(
            "select search_groups_minimal($1::jsonb, $2::int)",
            &[&Json(filters), &limit],
        )
        .await
    }
}
