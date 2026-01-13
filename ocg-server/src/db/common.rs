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
    templates::site::explore,
    types::{
        community::{CommunityFull, CommunitySummary},
        event::{EventFull, EventSummary},
        group::{GroupFull, GroupSummary},
    },
};

/// Common database operations trait.
#[async_trait]
pub(crate) trait DBCommon {
    /// Retrieves community information by its unique identifier.
    async fn get_community_full(&self, community_id: Uuid) -> Result<CommunityFull>;

    /// Retrieves community summary by its unique identifier.
    async fn get_community_summary(&self, community_id: Uuid) -> Result<CommunitySummary>;

    /// Gets full event details.
    async fn get_event_full(&self, community_id: Uuid, group_id: Uuid, event_id: Uuid) -> Result<EventFull>;

    /// Gets summary event details.
    async fn get_event_summary(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        event_id: Uuid,
    ) -> Result<EventSummary>;

    /// Gets group full details.
    async fn get_group_full(&self, community_id: Uuid, group_id: Uuid) -> Result<GroupFull>;

    /// Gets group summary details.
    async fn get_group_summary(&self, community_id: Uuid, group_id: Uuid) -> Result<GroupSummary>;

    /// Lists all available timezones.
    async fn list_timezones(&self) -> Result<Vec<String>>;

    /// Searches for events based on provided filters.
    async fn search_events(&self, filters: &explore::EventsFilters) -> Result<SearchEventsOutput>;

    /// Searches for groups based on provided filters.
    async fn search_groups(&self, filters: &explore::GroupsFilters) -> Result<SearchGroupsOutput>;
}

#[async_trait]
impl DBCommon for PgDB {
    /// [`DBCommon::get_community_full`]
    #[instrument(skip(self), err)]
    async fn get_community_full(&self, community_id: Uuid) -> Result<CommunityFull> {
        #[cfg_attr(
            not(test),
            cached(
                time = 3600,
                key = "Uuid",
                convert = r#"{ community_id }"#,
                sync_writes = "by_key",
                result = true
            )
        )]
        async fn inner(db: Client, community_id: Uuid) -> Result<CommunityFull> {
            trace!("db: get community full");

            let row = db
                .query_one("select get_community_full($1::uuid)::text", &[&community_id])
                .await?;
            let community: CommunityFull = serde_json::from_str(&row.get::<_, String>(0))?;

            Ok(community)
        }

        let db = self.pool.get().await?;
        inner(db, community_id).await
    }

    /// [`DBCommon::get_community_summary`]
    #[instrument(skip(self), err)]
    async fn get_community_summary(&self, community_id: Uuid) -> Result<CommunitySummary> {
        trace!("db: get community summary");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_community_summary($1::uuid)::text", &[&community_id])
            .await?;
        let community: CommunitySummary = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(community)
    }

    /// [`DBCommon::get_event_full`]
    #[instrument(skip(self), err)]
    async fn get_event_full(&self, community_id: Uuid, group_id: Uuid, event_id: Uuid) -> Result<EventFull> {
        trace!("db: get event full");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_event_full($1::uuid, $2::uuid, $3::uuid)::text",
                &[&community_id, &group_id, &event_id],
            )
            .await?;
        let event = EventFull::try_from_json(&row.get::<_, String>(0))?;

        Ok(event)
    }

    /// [`DBCommon::get_event_summary`]
    #[instrument(skip(self), err)]
    async fn get_event_summary(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        event_id: Uuid,
    ) -> Result<EventSummary> {
        trace!("db: get event summary");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_event_summary($1::uuid, $2::uuid, $3::uuid)::text",
                &[&community_id, &group_id, &event_id],
            )
            .await?;
        let event = EventSummary::try_from_json(&row.get::<_, String>(0))?;

        Ok(event)
    }

    /// [`DBCommon::get_group_full`]
    #[instrument(skip(self), err)]
    async fn get_group_full(&self, community_id: Uuid, group_id: Uuid) -> Result<GroupFull> {
        trace!("db: get group full");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_group_full($1::uuid, $2::uuid)::text",
                &[&community_id, &group_id],
            )
            .await?;
        let group = GroupFull::try_from_json(&row.get::<_, String>(0))?;

        Ok(group)
    }

    /// [`DBCommon::get_group_summary`]
    #[instrument(skip(self), err)]
    async fn get_group_summary(&self, community_id: Uuid, group_id: Uuid) -> Result<GroupSummary> {
        trace!("db: get group summary");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_group_summary($1::uuid, $2::uuid)::text",
                &[&community_id, &group_id],
            )
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

    /// [`DBCommon::search_events`]
    #[instrument(skip(self), err)]
    async fn search_events(&self, filters: &explore::EventsFilters) -> Result<SearchEventsOutput> {
        trace!("db: search events");

        // Query database
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "
                select events::text, bbox::text, total
                from search_events($1::jsonb)
                ",
                &[&Json(filters)],
            )
            .await?;

        // Prepare search output
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let output = SearchEventsOutput {
            events: EventSummary::try_from_json_array(&row.get::<_, String>("events"))?,
            bbox: if let Some(bbox) = row.get::<_, Option<String>>("bbox") {
                serde_json::from_str(&bbox)?
            } else {
                None
            },
            total: row.get::<_, i64>("total") as usize,
        };

        Ok(output)
    }

    /// [`DBCommon::search_groups`]
    #[instrument(skip(self), err)]
    async fn search_groups(&self, filters: &explore::GroupsFilters) -> Result<SearchGroupsOutput> {
        trace!("db: search groups");

        // Query database
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "
                select groups::text, bbox::text, total
                from search_groups($1::jsonb)
                ",
                &[&Json(filters)],
            )
            .await?;

        // Prepare search output
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let output = SearchGroupsOutput {
            groups: GroupSummary::try_from_json_array(&row.get::<_, String>("groups"))?,
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

/// Output structure for events search operations.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct SearchEventsOutput {
    pub events: Vec<EventSummary>,
    pub bbox: Option<BBox>,
    pub total: Total,
}

/// Output structure for groups search operations.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct SearchGroupsOutput {
    pub groups: Vec<GroupSummary>,
    pub bbox: Option<BBox>,
    pub total: Total,
}
