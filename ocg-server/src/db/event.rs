//! This module defines database functionality for the event page.

use anyhow::Result;
use async_trait::async_trait;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    types::event::{EventFull, EventSummary},
};

/// Database trait defining all data access operations for event page.
#[async_trait]
pub(crate) trait DBEvent {
    /// Adds a user as an attendee of an event.
    async fn attend_event(&self, community_id: Uuid, event_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Retrieves detailed event information.
    async fn get_event_full_by_slug(
        &self,
        community_id: Uuid,
        group_slug: &str,
        event_slug: &str,
    ) -> Result<EventFull>;

    /// Retrieves summary event information by its identifier.
    async fn get_event_summary_by_id(&self, community_id: Uuid, event_id: Uuid) -> Result<EventSummary>;

    /// Checks if a user is an attendee of an event.
    async fn is_event_attendee(&self, community_id: Uuid, event_id: Uuid, user_id: Uuid) -> Result<bool>;

    /// Removes a user from an event attendees.
    async fn leave_event(&self, community_id: Uuid, event_id: Uuid, user_id: Uuid) -> Result<()>;
}

#[async_trait]
impl DBEvent for PgDB {
    /// [`DB::attend_event`]
    #[instrument(skip(self), err)]
    async fn attend_event(&self, community_id: Uuid, event_id: Uuid, user_id: Uuid) -> Result<()> {
        trace!("db: attend event");

        let db = self.pool.get().await?;
        db.execute(
            "select attend_event($1::uuid, $2::uuid, $3::uuid)",
            &[&community_id, &event_id, &user_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBEvent::get_event_full_by_slug`]
    #[instrument(skip(self), err)]
    async fn get_event_full_by_slug(
        &self,
        community_id: Uuid,
        group_slug: &str,
        event_slug: &str,
    ) -> Result<EventFull> {
        trace!("db: get event");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_event($1::uuid, $2::text, $3::text)::text",
                &[&community_id, &group_slug, &event_slug],
            )
            .await?;
        let event = EventFull::try_from_json(row.get(0))?;

        Ok(event)
    }

    /// [`DBEvent::get_event_summary_by_id`]
    #[instrument(skip(self), err)]
    async fn get_event_summary_by_id(&self, community_id: Uuid, event_id: Uuid) -> Result<EventSummary> {
        trace!("db: get event summary by id");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_event_summary_by_id($1::uuid, $2::uuid)::text",
                &[&community_id, &event_id],
            )
            .await?;
        let event = EventSummary::try_from_json(row.get(0))?;

        Ok(event)
    }

    /// [`DB::is_event_attendee`]
    #[instrument(skip(self), err)]
    async fn is_event_attendee(&self, community_id: Uuid, event_id: Uuid, user_id: Uuid) -> Result<bool> {
        trace!("db: check event attendance");

        let db = self.pool.get().await?;
        let is_attendee = db
            .query_one(
                "select is_event_attendee($1::uuid, $2::uuid, $3::uuid)",
                &[&community_id, &event_id, &user_id],
            )
            .await?
            .get::<_, bool>(0);

        Ok(is_attendee)
    }

    /// [`DB::leave_event`]
    #[instrument(skip(self), err)]
    async fn leave_event(&self, community_id: Uuid, event_id: Uuid, user_id: Uuid) -> Result<()> {
        trace!("db: leave event");

        let db = self.pool.get().await?;
        db.execute(
            "select leave_event($1::uuid, $2::uuid, $3::uuid)",
            &[&community_id, &event_id, &user_id],
        )
        .await?;

        Ok(())
    }
}
