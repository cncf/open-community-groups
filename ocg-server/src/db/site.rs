//! This module defines some database functionality for the global site.

use anyhow::Result;
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::{instrument, trace};

use crate::{
    db::PgDB,
    templates::site::explore::{Entity, FiltersOptions},
    templates::site::stats::SiteStats,
    types::{
        community::CommunitySummary,
        event::{EventKind, EventSummary},
        group::GroupSummary,
        site::{SiteHomeStats, SiteSettings},
    },
};

/// Trait for database operations related to site.
#[async_trait]
#[allow(dead_code)]
pub(crate) trait DBSite {
    /// Retrieves filters options for the explore page. When a `community_name` is
    /// provided, community-specific filters are included. When `entity` is 'Events`
    /// and a community name is provided, groups are also included.
    async fn get_filters_options(
        &self,
        community_name: Option<String>,
        entity: Option<Entity>,
    ) -> Result<FiltersOptions>;

    /// Retrieves the site home stats.
    async fn get_site_home_stats(&self) -> Result<SiteHomeStats>;

    /// Retrieves the most recently added groups across all communities.
    async fn get_site_recently_added_groups(&self) -> Result<Vec<GroupSummary>>;

    /// Retrieves the site settings.
    async fn get_site_settings(&self) -> Result<SiteSettings>;

    /// Retrieves the site stats for the stats page.
    async fn get_site_stats(&self) -> Result<SiteStats>;

    /// Retrieves upcoming events across all communities.
    async fn get_site_upcoming_events(&self, event_kinds: Vec<EventKind>) -> Result<Vec<EventSummary>>;

    /// Lists all active communities.
    async fn list_communities(&self) -> Result<Vec<CommunitySummary>>;
}

/// Implementation of `DBSite` for `PgDB`.
#[async_trait]
impl DBSite for PgDB {
    #[instrument(skip(self), err)]
    async fn get_filters_options(
        &self,
        community_name: Option<String>,
        entity: Option<Entity>,
    ) -> Result<FiltersOptions> {
        trace!("db: get filters options");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_filters_options($1::text, $2::text)",
                &[&community_name, &entity.map(|e| e.to_string())],
            )
            .await?;
        let filters_options = row.try_get::<_, Json<FiltersOptions>>(0)?.0;

        Ok(filters_options)
    }

    #[instrument(skip(self), err)]
    async fn get_site_home_stats(&self) -> Result<SiteHomeStats> {
        trace!("db: get site home stats");

        let db = self.pool.get().await?;
        let row = db.query_one("select get_site_home_stats()", &[]).await?;
        let stats = row.try_get::<_, Json<SiteHomeStats>>(0)?.0;

        Ok(stats)
    }

    #[instrument(skip(self), err)]
    async fn get_site_recently_added_groups(&self) -> Result<Vec<GroupSummary>> {
        trace!("db: get site recently added groups");

        let db = self.pool.get().await?;
        let row = db.query_one("select get_site_recently_added_groups()", &[]).await?;
        let groups = row.try_get::<_, Json<Vec<GroupSummary>>>(0)?.0;

        Ok(groups)
    }

    #[instrument(skip(self), err)]
    async fn get_site_settings(&self) -> Result<SiteSettings> {
        trace!("db: get site settings");

        let db = self.pool.get().await?;
        let row = db.query_one("select get_site_settings()", &[]).await?;
        let settings = row.try_get::<_, Json<SiteSettings>>(0)?.0;

        Ok(settings)
    }

    #[instrument(skip(self), err)]
    async fn get_site_stats(&self) -> Result<SiteStats> {
        trace!("db: get site stats");

        let db = self.pool.get().await?;
        let row = db.query_one("select get_site_stats()", &[]).await?;
        let stats = row.try_get::<_, Json<SiteStats>>(0)?.0;

        Ok(stats)
    }

    #[instrument(skip(self), err)]
    async fn get_site_upcoming_events(&self, event_kinds: Vec<EventKind>) -> Result<Vec<EventSummary>> {
        trace!("db: get site upcoming events");

        let event_kinds = event_kinds.into_iter().map(|k| k.to_string()).collect::<Vec<_>>();
        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_site_upcoming_events($1::text[])", &[&event_kinds])
            .await?;
        let events = row.try_get::<_, Json<Vec<EventSummary>>>(0)?.0;

        Ok(events)
    }

    #[instrument(skip(self), err)]
    async fn list_communities(&self) -> Result<Vec<CommunitySummary>> {
        trace!("db: list communities");

        let db = self.pool.get().await?;
        let row = db.query_one("select list_communities();", &[]).await?;
        let communities = row.try_get::<_, Json<Vec<CommunitySummary>>>(0)?.0;

        Ok(communities)
    }
}
