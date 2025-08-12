//! Database interface for group dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::dashboard::group::events::Event,
    types::event::{EventCategory, EventKindSummary as EventKind, EventSummary},
};

/// Database trait for group dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardGroup {
    /// Adds a new event to the database.
    async fn add_event(&self, group_id: Uuid, event: &Event) -> Result<Uuid>;

    /// Deletes an event (soft delete by setting deleted=true and `deleted_at`).
    async fn delete_event(&self, event_id: Uuid) -> Result<()>;

    /// Lists all event categories for a community.
    async fn list_event_categories(&self, community_id: Uuid) -> Result<Vec<EventCategory>>;

    /// Lists all available event kinds.
    async fn list_event_kinds(&self) -> Result<Vec<EventKind>>;

    /// Lists all events for a group for management.
    async fn list_group_events(&self, group_id: Uuid) -> Result<Vec<EventSummary>>;

    /// Updates an existing event.
    async fn update_event(&self, event_id: Uuid, event: &Event) -> Result<()>;
}

#[async_trait]
impl DBDashboardGroup for PgDB {
    /// [`DBDashboardGroup::add_event`]
    #[instrument(skip(self, event), err)]
    async fn add_event(&self, group_id: Uuid, event: &Event) -> Result<Uuid> {
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select add_event($1::uuid, $2::jsonb)::uuid",
                &[&group_id, &Json(event)],
            )
            .await?;
        Ok(row.get(0))
    }

    /// [`DBDashboardGroup::delete_event`]
    #[instrument(skip(self), err)]
    async fn delete_event(&self, event_id: Uuid) -> Result<()> {
        let db = self.pool.get().await?;
        db.execute("select delete_event($1::uuid)", &[&event_id]).await?;
        Ok(())
    }

    /// [`DBDashboardGroup::list_event_categories`]
    #[instrument(skip(self), err)]
    async fn list_event_categories(&self, community_id: Uuid) -> Result<Vec<EventCategory>> {
        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_event_categories($1::uuid)::text", &[&community_id])
            .await?;
        let categories: Vec<EventCategory> = serde_json::from_str(&row.get::<_, String>(0))?;
        Ok(categories)
    }

    /// [`DBDashboardGroup::list_event_kinds`]
    #[instrument(skip(self), err)]
    async fn list_event_kinds(&self) -> Result<Vec<EventKind>> {
        let db = self.pool.get().await?;
        let row = db.query_one("select list_event_kinds()::text", &[]).await?;
        let kinds: Vec<EventKind> = serde_json::from_str(&row.get::<_, String>(0))?;
        Ok(kinds)
    }

    /// [`DBDashboardGroup::list_group_events`]
    #[instrument(skip(self), err)]
    async fn list_group_events(&self, group_id: Uuid) -> Result<Vec<EventSummary>> {
        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_group_events($1::uuid)::text", &[&group_id])
            .await?;
        let events = EventSummary::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(events)
    }

    /// [`DBDashboardGroup::update_event`]
    #[instrument(skip(self, event), err)]
    async fn update_event(&self, event_id: Uuid, event: &Event) -> Result<()> {
        let db = self.pool.get().await?;
        db.execute(
            "select update_event($1::uuid, $2::jsonb)",
            &[&event_id, &Json(event)],
        )
        .await?;
        Ok(())
    }
}
