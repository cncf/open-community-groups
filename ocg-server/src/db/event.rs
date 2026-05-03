//! This module defines database functionality for the event page.

use anyhow::Result;
use async_trait::async_trait;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::event::SessionProposal,
    types::event::{EventAttendanceInfo, EventAttendanceStatus, EventFull, EventLeaveOutcome, EventSummary},
};

/// Database trait defining all data access operations for event page.
#[async_trait]
pub(crate) trait DBEvent {
    /// Adds a new CFS submission for an event.
    async fn add_cfs_submission(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
        session_proposal_id: Uuid,
        label_ids: &[Uuid],
    ) -> Result<Uuid>;

    /// Registers attendance and returns the resulting attendance status.
    async fn attend_event(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
    ) -> Result<EventAttendanceStatus>;

    /// Marks an attendee as checked in for an event.
    async fn check_in_event(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
        bypass_window: bool,
    ) -> Result<()>;

    /// Ensures the event exists in the community and is active.
    async fn ensure_event_is_active(&self, community_id: Uuid, event_id: Uuid) -> Result<()>;

    /// Returns the user's attendance details and check-in status for an event.
    async fn get_event_attendance(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
    ) -> Result<EventAttendanceInfo>;

    /// Retrieves detailed event information.
    async fn get_event_full_by_slug(
        &self,
        community_id: Uuid,
        group_slug: &str,
        event_slug: &str,
    ) -> Result<Option<EventFull>>;

    /// Retrieves summary event information by its identifier.
    async fn get_event_summary_by_id(&self, community_id: Uuid, event_id: Uuid) -> Result<EventSummary>;

    /// Checks if the check-in window is open for an event.
    async fn is_event_check_in_window_open(&self, community_id: Uuid, event_id: Uuid) -> Result<bool>;

    /// Removes a user from an event and returns the leave outcome.
    async fn leave_event(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
    ) -> Result<EventLeaveOutcome>;

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
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
        session_proposal_id: Uuid,
        label_ids: &[Uuid],
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_cfs_submission($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid[])::uuid",
            &[
                &community_id,
                &event_id,
                &user_id,
                &session_proposal_id,
                &label_ids,
            ],
        )
        .await
    }

    /// [`DBEvent::attend_event`]
    #[instrument(skip(self), err)]
    async fn attend_event(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
    ) -> Result<EventAttendanceStatus> {
        let status: String = self
            .fetch_scalar_one(
                "select attend_event($1::uuid, $2::uuid, $3::uuid)::text",
                &[&community_id, &event_id, &user_id],
            )
            .await?;

        status
            .parse()
            .map_err(|_| anyhow::anyhow!("unknown attendance status returned by database: {status}"))
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
        self.execute(
            "select check_in_event($1::uuid, $2::uuid, $3::uuid, $4::bool)",
            &[&community_id, &event_id, &user_id, &bypass_window],
        )
        .await
    }

    /// [`DBEvent::ensure_event_is_active`]
    #[instrument(skip(self), err)]
    async fn ensure_event_is_active(&self, community_id: Uuid, event_id: Uuid) -> Result<()> {
        self.execute(
            "select ensure_event_is_active($1::uuid, $2::uuid)",
            &[&community_id, &event_id],
        )
        .await
    }

    /// [`DBEvent::get_event_attendance`]
    #[instrument(skip(self), err)]
    async fn get_event_attendance(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
    ) -> Result<EventAttendanceInfo> {
        self.fetch_json_one(
            "select get_event_attendance($1::uuid, $2::uuid, $3::uuid)",
            &[&community_id, &event_id, &user_id],
        )
        .await
    }

    /// [`DBEvent::get_event_full_by_slug`]
    #[instrument(skip(self), err)]
    async fn get_event_full_by_slug(
        &self,
        community_id: Uuid,
        group_slug: &str,
        event_slug: &str,
    ) -> Result<Option<EventFull>> {
        self.fetch_json_opt(
            "select get_event_full_by_slug($1::uuid, $2::text, $3::text)",
            &[&community_id, &group_slug, &event_slug],
        )
        .await
    }

    /// [`DBEvent::get_event_summary_by_id`]
    #[instrument(skip(self), err)]
    async fn get_event_summary_by_id(&self, community_id: Uuid, event_id: Uuid) -> Result<EventSummary> {
        self.fetch_json_one(
            "select get_event_summary_by_id($1::uuid, $2::uuid)",
            &[&community_id, &event_id],
        )
        .await
    }

    /// [`DBEvent::is_event_check_in_window_open`]
    #[instrument(skip(self), err)]
    async fn is_event_check_in_window_open(&self, community_id: Uuid, event_id: Uuid) -> Result<bool> {
        self.fetch_scalar_one(
            "select is_event_check_in_window_open($1::uuid, $2::uuid)",
            &[&community_id, &event_id],
        )
        .await
    }

    /// [`DBEvent::leave_event`]
    #[instrument(skip(self), err)]
    async fn leave_event(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
    ) -> Result<EventLeaveOutcome> {
        self.fetch_json_one(
            "select leave_event($1::uuid, $2::uuid, $3::uuid)",
            &[&community_id, &event_id, &user_id],
        )
        .await
    }

    /// [`DBEvent::list_user_session_proposals_for_cfs_event`]
    #[instrument(skip(self), err)]
    async fn list_user_session_proposals_for_cfs_event(
        &self,
        user_id: Uuid,
        event_id: Uuid,
    ) -> Result<Vec<SessionProposal>> {
        self.fetch_json_one(
            "select list_user_session_proposals_for_cfs_event($1::uuid, $2::uuid)",
            &[&user_id, &event_id],
        )
        .await
    }
}
