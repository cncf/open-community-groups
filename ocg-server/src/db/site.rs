//! This module defines some database functionality for the global site.

use anyhow::Result;
use async_trait::async_trait;
use cached::cached;
use tokio_postgres::types::Json;
use tracing::instrument;

use crate::{
    db::{PgClient, PgExecutor},
    templates::site::explore::{Entity, FiltersOptions},
    templates::site::stats::SiteStats,
    types::{
        alliance::AllianceSummary,
        event::{EventKind, EventSummary},
        group::GroupSummary,
        site::{SiteHomeStats, SiteSettings},
    },
};

/// Trait for database operations related to site.
#[async_trait]
#[allow(dead_code)]
pub(crate) trait DBSite {
    /// Retrieves filters options for the explore page. When a `alliance_name` is
    /// provided, alliance-specific filters are included. When `entity` is 'Events`
    /// and a alliance name is provided, groups are also included.
    async fn get_filters_options(
        &self,
        alliance_name: Option<String>,
        entity: Option<Entity>,
    ) -> Result<FiltersOptions>;

    /// Retrieves the site home stats.
    async fn get_site_home_stats(&self) -> Result<SiteHomeStats>;

    /// Retrieves the most recently added groups across all alliances.
    async fn get_site_recently_added_groups(&self) -> Result<Vec<GroupSummary>>;

    /// Retrieves the site settings.
    async fn get_site_settings(&self) -> Result<SiteSettings>;

    /// Retrieves the site stats for the stats page.
    async fn get_site_stats(&self) -> Result<SiteStats>;

    /// Retrieves upcoming events across all alliances.
    async fn get_site_upcoming_events(
        &self,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>>;

    /// Lists all active alliances.
    async fn list_alliances(&self) -> Result<Vec<AllianceSummary>>;
}

#[async_trait]
impl<T> DBSite for T
where
    T: PgExecutor + Send + Sync,
{
    #[instrument(skip(self), err)]
    async fn get_filters_options(
        &self,
        alliance_name: Option<String>,
        entity: Option<Entity>,
    ) -> Result<FiltersOptions> {
        self.fetch_json_one(
            "select get_filters_options($1::text, $2::text)",
            &[&alliance_name, &entity.map(|e| e.to_string())],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn get_site_home_stats(&self) -> Result<SiteHomeStats> {
        self.fetch_json_one("select get_site_home_stats()", &[]).await
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
        self.fetch_json_one("select get_site_stats()", &[]).await
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
    async fn list_alliances(&self) -> Result<Vec<AllianceSummary>> {
        #[cached(
            ttl = 300,
            key = "String",
            convert = r#"{ String::from("alliances") }"#,
            sync_writes = "by_key"
        )]
        async fn inner(db: PgClient<'_>) -> Result<Vec<AllianceSummary>> {
            let row = db.query_one("select list_alliances();", &[]).await?;
            let alliances = row.try_get::<_, Json<Vec<AllianceSummary>>>(0)?.0;

            Ok(alliances)
        }

        let db = self.client().await?;
        inner(db).await
    }
}
