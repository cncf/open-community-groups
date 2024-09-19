//! This module defines an abstraction layer over the database.

use crate::handlers::community;
use anyhow::{Context, Result};
use async_trait::async_trait;
use deadpool_postgres::Pool;
use std::sync::Arc;
use uuid::Uuid;

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
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                r#"
                select json_strip_nulls(json_build_object(
                    'community', json_build_object(
                        'banners_urls', banners_urls,
                        'copyright_notice', copyright_notice,
                        'description', description,
                        'display_name', display_name,
                        'extra_links', extra_links,
                        'facebook_url', facebook_url,
                        'flickr_url', flickr_url,
                        'footer_logo_url', footer_logo_url,
                        'github_url', github_url,
                        'header_logo_url', header_logo_url,
                        'homepage_url', homepage_url,
                        'instagram_url', instagram_url,
                        'linkedin_url', linkedin_url,
                        'photos_urls', photos_urls,
                        'slack_url', slack_url,
                        'twitter_url', twitter_url,
                        'wechat_url', wechat_url,
                        'youtube_url', youtube_url
                    ),
                    'groups', (
                        select coalesce(json_agg(json_build_object(
                            'city', g.city,
                            'country', g.country,
                            'icon_url', g.icon_url,
                            'name', g.name,
                            'region_name', r.name,
                            'slug', g.slug
                        )), '[]')
                        from "group" g
                        join region r using (region_id)
                        where g.community_id = $1
                    ),
                    'upcoming_in_person_events', (
                        select coalesce(json_agg(json_build_object(
                            'group_name', group_name,
                            'icon_url', icon_url,
                            'slug', slug,
                            'starts_at', starts_at,
                            'title', title
                        )), '[]')
                        from (
                            select g.name as group_name, e.icon_url, e.slug, e.starts_at, e.title
                            from event e
                            join "group" g using (group_id)
                            where g.community_id = $1
                            and e.starts_at > now()
                            and e.cancelled = false
                            and e.postponed = false
                            and e.event_kind_id = 'in-person'
                            order by e.starts_at asc
                            limit 10
                        ) events
                    ),
                    'upcoming_online_events', (
                        select coalesce(json_agg(json_build_object(
                            'group_name', group_name,
                            'icon_url', icon_url,
                            'slug', slug,
                            'starts_at', starts_at,
                            'title', title
                        )), '[]')
                        from (
                            select g.name as group_name, e.icon_url, e.slug, e.starts_at, e.title
                            from event e
                            join "group" g using (group_id)
                            where g.community_id = $1
                            and e.starts_at > now()
                            and e.cancelled = false
                            and e.postponed = false
                            and e.event_kind_id = 'virtual'
                            order by e.starts_at asc
                            limit 10
                        ) events
                    )
                )) as json_data
                from community
                where community_id = $1
                "#,
                &[&community_id],
            )
            .await?;
        let index = serde_json::from_value(row.get("json_data"))
            .context("error deserializing index data")?;

        Ok(index)
    }
}
