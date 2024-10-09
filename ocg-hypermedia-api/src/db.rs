//! This module defines an abstraction layer over the database.

use crate::templates::community::{
    common::Community,
    explore::{self, EventsFilters, GroupsFilters},
    home,
};
use anyhow::Result;
use async_trait::async_trait;
use deadpool_postgres::Pool;
use std::sync::Arc;
use tokio_postgres::types::Json;
use uuid::Uuid;

/// Type alias to represent a string of json data.
pub(crate) type JsonString = String;

/// Abstraction layer over the database. Trait that defines some operations a
/// DB implementation must support.
#[async_trait]
pub(crate) trait DB {
    /// Get community data.
    async fn get_community(&self, community_id: Uuid) -> Result<Community>;

    /// Get community events filters options.
    async fn get_community_events_filters_options(
        &self,
        community_id: Uuid,
    ) -> Result<explore::EventsFiltersOptions>;

    /// Get the community id from the host provided.
    async fn get_community_id(&self, host: &str) -> Result<Option<Uuid>>;

    /// Get the groups recently added to the community.
    async fn get_community_recently_added_groups(&self, community_id: Uuid) -> Result<Vec<home::Group>>;

    /// Get the upcoming in-person events in the community.
    async fn get_community_upcoming_in_person_events(&self, community_id: Uuid) -> Result<Vec<home::Event>>;

    /// Get the upcoming virtual events in the community.
    async fn get_community_upcoming_virtual_events(&self, community_id: Uuid) -> Result<Vec<home::Event>>;

    /// Search community events that match the criteria provided.
    async fn search_community_events(
        &self,
        community_id: Uuid,
        filters: &EventsFilters,
    ) -> Result<Vec<explore::Event>>;

    /// Search community groups that match the criteria provided.
    async fn search_community_groups(
        &self,
        community_id: Uuid,
        filters: &GroupsFilters,
    ) -> Result<Vec<explore::Group>>;
}

/// Type alias to represent a DB trait object.
pub(crate) type DynDB = Arc<dyn DB + Send + Sync>;

/// DB implementation backed by `PostgreSQL`.
pub(crate) struct PgDB {
    pool: Pool,
}

impl PgDB {
    /// Create a new `PgDB` instance.
    pub(crate) fn new(pool: Pool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl DB for PgDB {
    /// [DB::get_community]
    async fn get_community(&self, community_id: Uuid) -> Result<Community> {
        let db = self.pool.get().await?;
        let data: JsonString = db
            .query_one("select get_community($1::uuid)::text", &[&community_id])
            .await?
            .get(0);
        let community = Community::try_from_json(&data)?;

        Ok(community)
    }

    /// [DB::get_community_events_filters_options]
    async fn get_community_events_filters_options(
        &self,
        community_id: Uuid,
    ) -> Result<explore::EventsFiltersOptions> {
        let db = self.pool.get().await?;
        let data: JsonString = db
            .query_one(
                "select get_community_events_filters_options($1::uuid)::text",
                &[&community_id],
            )
            .await?
            .get(0);
        let filters_options = explore::EventsFiltersOptions::try_from_json(&data)?;

        Ok(filters_options)
    }

    /// [DB::get_community_id]
    async fn get_community_id(&self, host: &str) -> Result<Option<Uuid>> {
        let db = self.pool.get().await?;
        let community_id = db
            .query_opt(
                "select community_id from community where host = $1::text",
                &[&host],
            )
            .await?
            .map(|row| row.get("community_id"));

        Ok(community_id)
    }

    /// [DB::get_community_recently_added_groups]
    async fn get_community_recently_added_groups(&self, community_id: Uuid) -> Result<Vec<home::Group>> {
        let db = self.pool.get().await?;
        let data: JsonString = db
            .query_one(
                "select get_community_recently_added_groups($1::uuid)::text",
                &[&community_id],
            )
            .await?
            .get(0);
        let groups = home::Group::try_new_vec_from_json(&data)?;

        Ok(groups)
    }

    /// [DB::get_community_upcoming_in_person_events]
    async fn get_community_upcoming_in_person_events(&self, community_id: Uuid) -> Result<Vec<home::Event>> {
        let db = self.pool.get().await?;
        let data: JsonString = db
            .query_one(
                "select get_community_upcoming_in_person_events($1::uuid)::text",
                &[&community_id],
            )
            .await?
            .get(0);
        let events = home::Event::try_new_vec_from_json(&data)?;

        Ok(events)
    }

    /// [DB::get_community_upcoming_virtual_events]
    async fn get_community_upcoming_virtual_events(&self, community_id: Uuid) -> Result<Vec<home::Event>> {
        let db = self.pool.get().await?;
        let data: JsonString = db
            .query_one(
                "select get_community_upcoming_virtual_events($1::uuid)::text",
                &[&community_id],
            )
            .await?
            .get(0);
        let events = home::Event::try_new_vec_from_json(&data)?;

        Ok(events)
    }

    /// [DB::search_community_events]
    async fn search_community_events(
        &self,
        community_id: Uuid,
        filters: &EventsFilters,
    ) -> Result<Vec<explore::Event>> {
        let db = self.pool.get().await?;
        let data: JsonString = db
            .query_one(
                "select search_community_events($1::uuid, $2::jsonb)::text",
                &[&community_id, &Json(filters)],
            )
            .await?
            .get(0);
        let events = explore::Event::try_new_vec_from_json(&data)?;

        Ok(events)
    }

    /// [DB::search_community_groups]
    async fn search_community_groups(
        &self,
        community_id: Uuid,
        filters: &GroupsFilters,
    ) -> Result<Vec<explore::Group>> {
        let db = self.pool.get().await?;
        let data: JsonString = db
            .query_one(
                "select search_community_groups($1::uuid, $2::jsonb)::text",
                &[&community_id, &Json(filters)],
            )
            .await?
            .get(0);
        let groups = explore::Group::try_new_vec_from_json(&data)?;

        Ok(groups)
    }
}
