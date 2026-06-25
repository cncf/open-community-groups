//! Common database operations shared across different modules.

use anyhow::Result;
use async_trait::async_trait;
use cached::cached;
use serde::{Deserialize, Serialize};
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::{BBox, PgClient, PgExecutor, Total},
    types::{
        alliance::{AllianceFull, AllianceSummary},
        event::{EventCfsLabel, EventFull, EventSummary},
        group::{GroupFull, GroupSummary},
        search::{SearchEventsFilters, SearchGroupsFilters},
    },
};

/// Common database operations trait.
#[async_trait]
pub(crate) trait DBCommon {
    /// Retrieves alliance information by its unique identifier.
    async fn get_alliance_full(&self, alliance_id: Uuid) -> Result<AllianceFull>;

    /// Retrieves alliance summary by its unique identifier.
    async fn get_alliance_summary(&self, alliance_id: Uuid) -> Result<AllianceSummary>;

    /// Gets full event details.
    async fn get_event_full(
        &self,
        alliance_id: Uuid,
        group_id: Uuid,
        event_id: Uuid,
    ) -> Result<EventFull>;

    /// Gets summary event details.
    async fn get_event_summary(
        &self,
        alliance_id: Uuid,
        group_id: Uuid,
        event_id: Uuid,
    ) -> Result<EventSummary>;

    /// Gets group full details.
    async fn get_group_full(&self, alliance_id: Uuid, group_id: Uuid) -> Result<GroupFull>;

    /// Gets group summary details.
    async fn get_group_summary(&self, alliance_id: Uuid, group_id: Uuid) -> Result<GroupSummary>;

    /// Lists labels configured for an event.
    async fn list_event_cfs_labels(&self, event_id: Uuid) -> Result<Vec<EventCfsLabel>>;

    /// Lists all available timezones.
    async fn list_timezones(&self) -> Result<Vec<String>>;

    /// Searches for events based on provided filters.
    async fn search_events(&self, filters: &SearchEventsFilters) -> Result<SearchEventsOutput>;

    /// Searches for groups based on provided filters.
    async fn search_groups(&self, filters: &SearchGroupsFilters) -> Result<SearchGroupsOutput>;
}

#[async_trait]
impl<T> DBCommon for T
where
    T: PgExecutor + Send + Sync,
{
    /// [`DBCommon::get_alliance_full`]
    #[instrument(skip(self), err)]
    async fn get_alliance_full(&self, alliance_id: Uuid) -> Result<AllianceFull> {
        self.fetch_json_one("select get_alliance_full($1::uuid)", &[&alliance_id])
            .await
    }

    /// [`DBCommon::get_alliance_summary`]
    #[instrument(skip(self), err)]
    async fn get_alliance_summary(&self, alliance_id: Uuid) -> Result<AllianceSummary> {
        self.fetch_json_one("select get_alliance_summary($1::uuid)", &[&alliance_id])
            .await
    }

    /// [`DBCommon::get_event_full`]
    #[instrument(skip(self), err)]
    async fn get_event_full(
        &self,
        alliance_id: Uuid,
        group_id: Uuid,
        event_id: Uuid,
    ) -> Result<EventFull> {
        self.fetch_json_one(
            "select get_event_full($1::uuid, $2::uuid, $3::uuid)",
            &[&alliance_id, &group_id, &event_id],
        )
        .await
    }

    /// [`DBCommon::get_event_summary`]
    #[instrument(skip(self), err)]
    async fn get_event_summary(
        &self,
        alliance_id: Uuid,
        group_id: Uuid,
        event_id: Uuid,
    ) -> Result<EventSummary> {
        self.fetch_json_one(
            "select get_event_summary($1::uuid, $2::uuid, $3::uuid)",
            &[&alliance_id, &group_id, &event_id],
        )
        .await
    }

    /// [`DBCommon::get_group_full`]
    #[instrument(skip(self), err)]
    async fn get_group_full(&self, alliance_id: Uuid, group_id: Uuid) -> Result<GroupFull> {
        self.fetch_json_one(
            "select get_group_full($1::uuid, $2::uuid)",
            &[&alliance_id, &group_id],
        )
        .await
    }

    /// [`DBCommon::get_group_summary`]
    #[instrument(skip(self), err)]
    async fn get_group_summary(&self, alliance_id: Uuid, group_id: Uuid) -> Result<GroupSummary> {
        self.fetch_json_one(
            "select get_group_summary($1::uuid, $2::uuid)",
            &[&alliance_id, &group_id],
        )
        .await
    }

    /// [`DBCommon::list_event_cfs_labels`]
    #[instrument(skip(self), err)]
    async fn list_event_cfs_labels(&self, event_id: Uuid) -> Result<Vec<EventCfsLabel>> {
        self.fetch_json_one("select list_event_cfs_labels($1::uuid)", &[&event_id])
            .await
    }

    /// [`DBCommon::list_timezones`]
    #[instrument(skip(self), err)]
    async fn list_timezones(&self) -> Result<Vec<String>> {
        #[cached(
            ttl = 86400,
            key = "String",
            convert = r#"{ String::from("timezones") }"#,
            sync_writes = "by_key"
        )]
        async fn inner(db: PgClient<'_>) -> Result<Vec<String>> {
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

        let db = self.client().await?;
        inner(db).await
    }

    /// [`DBCommon::search_events`]
    #[instrument(skip(self), err)]
    async fn search_events(&self, filters: &SearchEventsFilters) -> Result<SearchEventsOutput> {
        self.fetch_json_one("select search_events($1::jsonb)", &[&Json(filters)])
            .await
    }

    /// [`DBCommon::search_groups`]
    #[instrument(skip(self), err)]
    async fn search_groups(&self, filters: &SearchGroupsFilters) -> Result<SearchGroupsOutput> {
        self.fetch_json_one("select search_groups($1::jsonb)", &[&Json(filters)])
            .await
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
