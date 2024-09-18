//! This module defines an abstraction layer over the database.

use anyhow::Result;
use async_trait::async_trait;
use deadpool_postgres::Pool;
use std::sync::Arc;
use uuid::Uuid;

use crate::handlers::community;

/// Abstraction layer over the database. Trait that defines some operations a
/// DB implementation must support.
#[async_trait]
pub(crate) trait DB {
    /// Get the community id from the host provided.
    async fn get_community_id(&self, host: &str) -> Result<Option<Uuid>>;

    /// Get data for the community index template.
    async fn get_community_index_data(&self, community_id: Uuid) -> Result<community::Index>;
}

/// Type alias to represent a DB trait object.
pub(crate) type DynDB = Arc<dyn DB + Send + Sync>;

/// DB implementation backed by PostgreSQL.
pub(crate) struct PgDB {
    pool: Pool,
}

impl PgDB {
    /// Create a new PgDB instance.
    pub(crate) fn new(pool: Pool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl DB for PgDB {
    /// [DB::get_community_name]
    async fn get_community_id(&self, host: &str) -> Result<Option<Uuid>> {
        let db = self.pool.get().await?;
        let community_id = db
            .query_opt(
                "select community_id from community where host = $1",
                &[&host],
            )
            .await?
            .map(|row| row.get("community_id"));

        Ok(community_id)
    }

    /// [DB::get_community_index_data]
    async fn get_community_index_data(&self, community_id: Uuid) -> Result<community::Index> {
        // Get community index data from database
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "
                select
                    banners_urls,
                    copyright_notice,
                    description,
                    display_name,
                    extra_links,
                    facebook_url,
                    flickr_url,
                    footer_logo_url,
                    github_url,
                    header_logo_url,
                    homepage_url,
                    instagram_url,
                    linkedin_url,
                    photos_urls,
                    slack_url,
                    twitter_url,
                    wechat_url,
                    youtube_url
                from community
                where community_id = $1
                ",
                &[&community_id],
            )
            .await?;

        // Prepare community index data
        let mut index = community::Index {
            banners_urls: row.get("banners_urls"),
            copyright_notice: row.get("copyright_notice"),
            description: row.get("description"),
            display_name: row.get("display_name"),
            extra_links: None,
            facebook_url: row.get("facebook_url"),
            flickr_url: row.get("flickr_url"),
            footer_logo_url: row.get("footer_logo_url"),
            github_url: row.get("github_url"),
            header_logo_url: row.get("header_logo_url"),
            homepage_url: row.get("homepage_url"),
            instagram_url: row.get("instagram_url"),
            linkedin_url: row.get("linkedin_url"),
            photos_urls: row.get("photos_urls"),
            slack_url: row.get("slack_url"),
            twitter_url: row.get("twitter_url"),
            wechat_url: row.get("wechat_url"),
            youtube_url: row.get("youtube_url"),
        };
        let extra_links: Option<serde_json::Value> = row.get("extra_links");
        if let Some(extra_links) = extra_links {
            if let Ok(extra_links) = serde_json::from_value(extra_links) {
                index.extra_links = Some(extra_links);
            }
        }

        Ok(index)
    }
}
