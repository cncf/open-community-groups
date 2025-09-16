//! Common database operations shared across different modules.

use std::time::Duration;

use anyhow::Result;
use async_trait::async_trait;
use cached::proc_macro::cached;
use deadpool_postgres::Client;
use serde::{Deserialize, Serialize};
use tokio_postgres::types::Json;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::{BBox, PgDB, Total},
    templates::community::explore,
    types::{
        community::Community,
        event::{EventDetailed, EventFull, EventSummary},
        group::{GroupDetailed, GroupFull, GroupSummary},
    },
};

/// Common database operations trait.
#[async_trait]
pub(crate) trait DBCommon {
    /// Retrieves community information by its unique identifier.
    async fn get_community(&self, community_id: Uuid) -> Result<Community>;

    /// Gets full event details.
    async fn get_event_full(&self, event_id: Uuid) -> Result<EventFull>;

    /// Gets summary event details.
    async fn get_event_summary(&self, event_id: Uuid) -> Result<EventSummary>;

    /// Gets group full details.
    async fn get_group_full(&self, group_id: Uuid) -> Result<GroupFull>;

    /// Gets group summary details.
    async fn get_group_summary(&self, group_id: Uuid) -> Result<GroupSummary>;

    /// Lists all available timezones.
    async fn list_timezones(&self) -> Result<Vec<String>>;

    /// Searches for community events based on provided filters.
    async fn search_community_events(
        &self,
        community_id: Uuid,
        filters: &explore::EventsFilters,
    ) -> Result<SearchCommunityEventsOutput>;

    /// Searches for community groups based on provided filters.
    async fn search_community_groups(
        &self,
        community_id: Uuid,
        filters: &explore::GroupsFilters,
    ) -> Result<SearchCommunityGroupsOutput>;
}

#[async_trait]
impl DBCommon for PgDB {
    /// [`DBCommon::get_community`]
    #[instrument(skip(self), err)]
    async fn get_community(&self, community_id: Uuid) -> Result<Community> {
        trace!("db: get community");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_community($1::uuid)::text", &[&community_id])
            .await?;
        let community = Community::try_from_json(&row.get::<_, String>(0))?;

        Ok(community)
    }

    /// [`DBCommon::get_event_full`]
    #[instrument(skip(self), err)]
    async fn get_event_full(&self, event_id: Uuid) -> Result<EventFull> {
        trace!("db: get event full");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_event_full($1::uuid)::text", &[&event_id])
            .await?;
        let event = EventFull::try_from_json(&row.get::<_, String>(0))?;

        Ok(event)
    }

    /// [`DBCommon::get_event_summary`]
    #[instrument(skip(self), err)]
    async fn get_event_summary(&self, event_id: Uuid) -> Result<EventSummary> {
        trace!("db: get event summary");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_event_summary($1::uuid)::text", &[&event_id])
            .await?;
        let event = EventSummary::try_from_json(&row.get::<_, String>(0))?;

        Ok(event)
    }

    /// [`DBCommon::get_group_full`]
    #[instrument(skip(self), err)]
    async fn get_group_full(&self, group_id: Uuid) -> Result<GroupFull> {
        trace!("db: get group full");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_group_full($1::uuid)::text", &[&group_id])
            .await?;
        let group = GroupFull::try_from_json(&row.get::<_, String>(0))?;

        Ok(group)
    }

    /// [`DBCommon::get_group_summary`]
    #[instrument(skip(self), err)]
    async fn get_group_summary(&self, group_id: Uuid) -> Result<GroupSummary> {
        trace!("db: get group summary");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_group_summary($1::uuid)::text", &[&group_id])
            .await?;
        let group = GroupSummary::try_from_json(&row.get::<_, String>(0))?;

        Ok(group)
    }

    /// [`DBCommon::list_timezones`]
    #[instrument(skip(self), err)]
    async fn list_timezones(&self) -> Result<Vec<String>> {
        #[cached(
            time = 86400,
            key = "String",
            convert = r#"{ String::from("timezones") }"#,
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client) -> Result<Vec<String>> {
            trace!("db: list timezones");

            let timezones = db
                .query(
                    "
                    select name
                    from pg_timezone_names
                    where name not like 'posix%'
                    and name not like 'SystemV%'
                    order by name asc;
                    ",
                    &[],
                )
                .await?
                .into_iter()
                .map(|row| row.get("name"))
                .collect();

            Ok(timezones)
        }

        let db = self.pool.get().await?;
        inner(db).await
    }

    /// [`DBCommon::search_community_events`]
    #[instrument(skip(self), err)]
    async fn search_community_events(
        &self,
        community_id: Uuid,
        filters: &explore::EventsFilters,
    ) -> Result<SearchCommunityEventsOutput> {
        trace!("db: search community events");

        // Query database
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "
                select events::text, bbox::text, total
                from search_community_events($1::uuid, $2::jsonb)
                ",
                &[&community_id, &Json(filters)],
            )
            .await?;

        // Prepare search output
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let output = SearchCommunityEventsOutput {
            events: EventDetailed::try_from_json_array(&row.get::<_, String>("events"))?,
            bbox: if let Some(bbox) = row.get::<_, Option<String>>("bbox") {
                serde_json::from_str(&bbox)?
            } else {
                None
            },
            total: row.get::<_, i64>("total") as usize,
        };

        Ok(output)
    }

    /// [`DBCommon::search_community_groups`]
    #[instrument(skip(self), err)]
    async fn search_community_groups(
        &self,
        community_id: Uuid,
        filters: &explore::GroupsFilters,
    ) -> Result<SearchCommunityGroupsOutput> {
        trace!("db: search community groups");

        // Query database
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "
                select groups::text, bbox::text, total
                from search_community_groups($1::uuid, $2::jsonb)
                ",
                &[&community_id, &Json(filters)],
            )
            .await?;

        // Prepare search output
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let output = SearchCommunityGroupsOutput {
            groups: GroupDetailed::try_from_json_array(&row.get::<_, String>("groups"))?,
            bbox: if let Some(bbox) = row.get::<_, Option<String>>("bbox") {
                serde_json::from_str(&bbox)?
            } else {
                None
            },
            total: row.get::<_, i64>("total") as usize,
        };

        Ok(output)
    }
}

/// Output structure for community events search operations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SearchCommunityEventsOutput {
    pub events: Vec<EventDetailed>,
    pub bbox: Option<BBox>,
    pub total: Total,
}

/// Output structure for community groups search operations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SearchCommunityGroupsOutput {
    pub groups: Vec<GroupDetailed>,
    pub bbox: Option<BBox>,
    pub total: Total,
}
