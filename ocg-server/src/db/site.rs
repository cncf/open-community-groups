//! Database operations for site-related functionality.

use anyhow::Result;
use async_trait::async_trait;
use tap::Pipe;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::site::explore::FiltersOptions,
    types::{
        community::CommunitySummary,
        site::{SiteHomeStats, SiteSettings},
    },
};

/// Trait for database operations related to site.
#[async_trait]
#[allow(dead_code)]
pub(crate) trait DBSite {
    /// Retrieves filters options for the explore page. When a `community_id` is
    /// provided, community-specific filters are included.
    async fn get_filters_options(&self, community_id: Option<Uuid>) -> Result<FiltersOptions>;

    /// Retrieves the site home stats.
    async fn get_site_home_stats(&self) -> Result<SiteHomeStats>;

    /// Retrieves the site settings.
    async fn get_site_settings(&self) -> Result<SiteSettings>;

    /// Lists all active communities.
    async fn list_communities(&self) -> Result<Vec<CommunitySummary>>;
}

/// Implementation of `DBSite` for `PgDB`.
#[async_trait]
impl DBSite for PgDB {
    #[instrument(skip(self), err)]
    async fn get_filters_options(&self, community_id: Option<Uuid>) -> Result<FiltersOptions> {
        trace!("db: get filters options");

        self.pool
            .get()
            .await?
            .query_one("select get_filters_options($1::uuid)::text", &[&community_id])
            .await?
            .get::<_, String>(0)
            .as_str()
            .pipe(FiltersOptions::try_from_json)
    }

    #[instrument(skip(self), err)]
    async fn get_site_home_stats(&self) -> Result<SiteHomeStats> {
        trace!("db: get site home stats");

        self.pool
            .get()
            .await?
            .query_one("select get_site_home_stats()::text", &[])
            .await?
            .get::<_, String>(0)
            .as_str()
            .pipe(SiteHomeStats::try_from_json)
    }

    #[instrument(skip(self), err)]
    async fn get_site_settings(&self) -> Result<SiteSettings> {
        trace!("db: get site settings");

        self.pool
            .get()
            .await?
            .query_one("select get_site_settings()::text", &[])
            .await?
            .get::<_, String>(0)
            .as_str()
            .pipe(SiteSettings::try_from_json)
    }

    #[instrument(skip(self), err)]
    async fn list_communities(&self) -> Result<Vec<CommunitySummary>> {
        trace!("db: list communities");

        let db = self.pool.get().await?;
        let communities: Vec<CommunitySummary> = db
            .query_one("select list_communities()::text;", &[])
            .await?
            .get::<_, String>(0)
            .as_str()
            .pipe(serde_json::from_str)?;

        Ok(communities)
    }
}
