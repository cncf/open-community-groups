//! This module defines database functionality for the event page.

use anyhow::Result;
use async_trait::async_trait;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::event::SessionProposal,
    types::event::{EventFull, EventSummary},
};

/// Database trait defining all data access operations for event page.
#[async_trait]
pub(crate) trait DBEvent {
    /// Adds a new CFS submission for an event.
    async fn add_cfs_submission(
        &self,
        user_id: Uuid,
        event_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<Uuid>;

    /// Adds a user as an attendee of an event.
    async fn attend_event(&self, community_id: Uuid, event_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Marks an attendee as checked in for an event.
    async fn check_in_event(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
        bypass_window: bool,
    ) -> Result<()>;

    /// Retrieves detailed event information.
    async fn get_event_full_by_slug(
        &self,
        community_id: Uuid,
        group_slug: &str,
        event_slug: &str,
    ) -> Result<EventFull>;

    /// Retrieves summary event information by its identifier.
    async fn get_event_summary_by_id(&self, community_id: Uuid, event_id: Uuid) -> Result<EventSummary>;

    /// Checks if a user is an attendee of an event and their check-in status.
    async fn is_event_attendee(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
    ) -> Result<(bool, bool)>;

    /// Checks if the check-in window is open for an event.
    async fn is_event_check_in_window_open(&self, community_id: Uuid, event_id: Uuid) -> Result<bool>;

    /// Removes a user from an event attendees.
    async fn leave_event(&self, community_id: Uuid, event_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Lists session proposals with submission status for a given event.
    async fn list_user_session_proposals_for_cfs_event(
        &self,
        user_id: Uuid,
        event_id: Uuid,
    ) -> Result<Vec<SessionProposal>>;
}

#[async_trait]
impl DBEvent for PgDB {
    /// [`DBEvent::add_cfs_submission`]
    #[instrument(skip(self), err)]
    async fn add_cfs_submission(
        &self,
        user_id: Uuid,
        event_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<Uuid> {
        trace!("db: add cfs submission");

        let db = self.pool.get().await?;
        let id = db
            .query_one(
                "select add_cfs_submission($1::uuid, $2::uuid, $3::uuid)::uuid",
                &[&user_id, &event_id, &session_proposal_id],
            )
            .await?
            .get(0);

        Ok(id)
    }

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

    /// [`DBEvent::check_in_event`]
    #[instrument(skip(self), err)]
    async fn check_in_event(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
        bypass_window: bool,
    ) -> Result<()> {
        trace!("db: check in event");

        let db = self.pool.get().await?;
        db.execute(
            "select check_in_event($1::uuid, $2::uuid, $3::uuid, $4::bool)",
            &[&community_id, &event_id, &user_id, &bypass_window],
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
                "select get_event_full_by_slug($1::uuid, $2::text, $3::text)::text",
                &[&community_id, &group_slug, &event_slug],
            )
            .await?;
        let event: EventFull = serde_json::from_str(row.get(0))?;

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
        let event: EventSummary = serde_json::from_str(row.get(0))?;

        Ok(event)
    }

    /// [`DB::is_event_attendee`]
    #[instrument(skip(self), err)]
    async fn is_event_attendee(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
    ) -> Result<(bool, bool)> {
        trace!("db: check event attendance");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select * from is_event_attendee($1::uuid, $2::uuid, $3::uuid)",
                &[&community_id, &event_id, &user_id],
            )
            .await?;
        let is_attendee = row.get::<_, bool>(0);
        let is_checked_in = row.get::<_, bool>(1);

        Ok((is_attendee, is_checked_in))
    }

    /// [`DBEvent::is_event_check_in_window_open`]
    #[instrument(skip(self), err)]
    async fn is_event_check_in_window_open(&self, community_id: Uuid, event_id: Uuid) -> Result<bool> {
        trace!("db: check event check-in window open");

        let db = self.pool.get().await?;
        let is_open = db
            .query_one(
                "select is_event_check_in_window_open($1::uuid, $2::uuid)",
                &[&community_id, &event_id],
            )
            .await?
            .get::<_, bool>(0);

        Ok(is_open)
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

    /// [`DBEvent::list_user_session_proposals_for_cfs_event`]
    #[instrument(skip(self), err)]
    async fn list_user_session_proposals_for_cfs_event(
        &self,
        user_id: Uuid,
        event_id: Uuid,
    ) -> Result<Vec<SessionProposal>> {
        trace!("db: list user session proposals for cfs event");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select list_user_session_proposals_for_cfs_event($1::uuid, $2::uuid)::text",
                &[&user_id, &event_id],
            )
            .await?;
        let proposals_json: String = row.get(0);
        let proposals: Vec<SessionProposal> = serde_json::from_str(&proposals_json)?;

        Ok(proposals)
    }
}
