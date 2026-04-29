//! This module defines database functionality used to manage meeting synchronization.

use std::time::Duration;

use anyhow::Result;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::Deserialize;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    PgDB,
    services::meetings::{Meeting, MeetingAutoEndCheckOutcome, MeetingProvider},
};

/// Trait that defines database operations used to manage meetings.
#[async_trait]
pub(crate) trait DBMeetings {
    /// Adds a new meeting and completes the sync claim.
    async fn add_meeting(&self, meeting: &Meeting) -> Result<()>;

    /// Reserves an available Zoom host user for a claimed meeting time window.
    async fn assign_zoom_host_user(
        &self,
        meeting: &Meeting,
        pool_users: &[String],
        max_simultaneous_meetings_per_user: i32,
        starts_at: DateTime<Utc>,
        ends_at: DateTime<Utc>,
    ) -> Result<Option<String>>;

    /// Claims one overdue meeting for auto-end checks.
    async fn claim_meeting_for_auto_end(&self) -> Result<Option<MeetingAutoEndCandidate>>;

    /// Claims a meeting that is out of sync.
    async fn claim_meeting_out_of_sync(&self) -> Result<Option<Meeting>>;

    /// Deletes a meeting and completes the sync claim.
    async fn delete_meeting(&self, meeting: &Meeting) -> Result<()>;

    /// Marks stale auto-end check claims with an unknown outcome.
    async fn mark_stale_meeting_auto_end_checks_unknown(&self, timeout: Duration) -> Result<usize>;

    /// Marks stale meeting sync claims with an unknown outcome.
    async fn mark_stale_meeting_syncs_unknown(&self, timeout: Duration) -> Result<usize>;

    /// Releases a retryable auto-end check claim.
    async fn release_meeting_auto_end_check_claim(&self, meeting_id: Uuid) -> Result<()>;

    /// Releases a retryable sync claim.
    async fn release_meeting_sync_claim(&self, meeting: &Meeting) -> Result<()>;

    /// Records the outcome of an auto-end check for a meeting.
    async fn set_meeting_auto_end_check_outcome(
        &self,
        meeting_id: Uuid,
        outcome: MeetingAutoEndCheckOutcome,
    ) -> Result<()>;

    /// Records an error for a meeting and completes the sync claim.
    async fn set_meeting_error(&self, meeting: &Meeting, error: &str) -> Result<()>;

    /// Updates meeting details and completes the sync claim.
    async fn update_meeting(&self, meeting: &Meeting) -> Result<()>;

    /// Updates the recording URL for a meeting by its provider and provider meeting ID.
    async fn update_meeting_recording_url(
        &self,
        provider: MeetingProvider,
        provider_meeting_id: &str,
        recording_url: &str,
    ) -> Result<()>;
}

#[async_trait]
impl DBMeetings for PgDB {
    #[instrument(skip(self, meeting), err)]
    async fn add_meeting(&self, meeting: &Meeting) -> Result<()> {
        self.execute(
            "select add_meeting($1, $2, $3, $4, $5, $6, $7, $8, $9)",
            &[
                &meeting.provider.as_ref(),
                &meeting.provider_meeting_id,
                &meeting.provider_host_user_id,
                &meeting.join_url,
                &meeting.password,
                &meeting.event_id,
                &meeting.session_id,
                &meeting.sync_claimed_at,
                &meeting.sync_state_hash,
            ],
        )
        .await?;

        Ok(())
    }

    #[instrument(skip(self, meeting, pool_users), err)]
    async fn assign_zoom_host_user(
        &self,
        meeting: &Meeting,
        pool_users: &[String],
        max_simultaneous_meetings_per_user: i32,
        starts_at: DateTime<Utc>,
        ends_at: DateTime<Utc>,
    ) -> Result<Option<String>> {
        self.fetch_scalar_one(
            "
            select assign_zoom_host_user(
                $1::uuid,
                $2::uuid,
                $3::timestamptz,
                $4::text[],
                $5::int4,
                $6::timestamptz,
                $7::timestamptz
            );
            ",
            &[
                &meeting.event_id,
                &meeting.session_id,
                &meeting.sync_claimed_at,
                &pool_users,
                &max_simultaneous_meetings_per_user,
                &starts_at,
                &ends_at,
            ],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn claim_meeting_for_auto_end(&self) -> Result<Option<MeetingAutoEndCandidate>> {
        self.fetch_json_opt("select claim_meeting_for_auto_end()", &[]).await
    }

    #[instrument(skip(self), err)]
    async fn claim_meeting_out_of_sync(&self) -> Result<Option<Meeting>> {
        self.fetch_json_opt("select claim_meeting_out_of_sync()", &[]).await
    }

    #[instrument(skip(self, meeting), err)]
    async fn delete_meeting(&self, meeting: &Meeting) -> Result<()> {
        self.execute(
            "select delete_meeting($1, $2, $3, $4, $5)",
            &[
                &meeting.meeting_id,
                &meeting.event_id,
                &meeting.session_id,
                &meeting.sync_claimed_at,
                &meeting.sync_state_hash,
            ],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn mark_stale_meeting_auto_end_checks_unknown(&self, timeout: Duration) -> Result<usize> {
        let timeout_seconds = i64::try_from(timeout.as_secs())
            .map_err(|_| anyhow::anyhow!("processing timeout cannot exceed i64::MAX seconds"))?;

        let count = self
            .fetch_scalar_one::<i64>(
                "select mark_stale_meeting_auto_end_checks_unknown($1::bigint)::bigint;",
                &[&timeout_seconds],
            )
            .await?;

        usize::try_from(count).map_err(|_| anyhow::anyhow!("stale auto-end claim count cannot be negative"))
    }

    #[instrument(skip(self), err)]
    async fn mark_stale_meeting_syncs_unknown(&self, timeout: Duration) -> Result<usize> {
        let timeout_seconds = i64::try_from(timeout.as_secs())
            .map_err(|_| anyhow::anyhow!("processing timeout cannot exceed i64::MAX seconds"))?;

        let count = self
            .fetch_scalar_one::<i64>(
                "select mark_stale_meeting_syncs_unknown($1::bigint)::bigint;",
                &[&timeout_seconds],
            )
            .await?;

        usize::try_from(count).map_err(|_| anyhow::anyhow!("stale sync claim count cannot be negative"))
    }

    #[instrument(skip(self), err)]
    async fn release_meeting_auto_end_check_claim(&self, meeting_id: Uuid) -> Result<()> {
        self.execute(
            "select release_meeting_auto_end_check_claim($1::uuid)",
            &[&meeting_id],
        )
        .await
    }

    #[instrument(skip(self, meeting), err)]
    async fn release_meeting_sync_claim(&self, meeting: &Meeting) -> Result<()> {
        self.execute(
            "select release_meeting_sync_claim($1::uuid, $2::uuid, $3::uuid, $4::timestamptz)",
            &[
                &meeting.event_id,
                &meeting.meeting_id,
                &meeting.session_id,
                &meeting.sync_claimed_at,
            ],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn set_meeting_auto_end_check_outcome(
        &self,
        meeting_id: Uuid,
        outcome: MeetingAutoEndCheckOutcome,
    ) -> Result<()> {
        self.execute(
            "select set_meeting_auto_end_check_outcome($1::uuid, $2::text)",
            &[&meeting_id, &outcome.as_ref()],
        )
        .await
    }

    #[instrument(skip(self, meeting), err)]
    async fn set_meeting_error(&self, meeting: &Meeting, error: &str) -> Result<()> {
        self.execute(
            "select set_meeting_error($1::text, $2::uuid, $3::uuid, $4::uuid, $5::timestamptz, $6::text)",
            &[
                &error,
                &meeting.event_id,
                &meeting.meeting_id,
                &meeting.session_id,
                &meeting.sync_claimed_at,
                &meeting.sync_state_hash,
            ],
        )
        .await
    }

    #[instrument(skip(self, meeting), err)]
    async fn update_meeting(&self, meeting: &Meeting) -> Result<()> {
        self.execute(
            "select update_meeting($1, $2, $3, $4, $5, $6, $7, $8)",
            &[
                &meeting.meeting_id,
                &meeting.provider_meeting_id,
                &meeting.join_url,
                &meeting.password,
                &meeting.event_id,
                &meeting.session_id,
                &meeting.sync_claimed_at,
                &meeting.sync_state_hash,
            ],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn update_meeting_recording_url(
        &self,
        provider: MeetingProvider,
        provider_meeting_id: &str,
        recording_url: &str,
    ) -> Result<()> {
        self.execute(
            "select update_meeting_recording_url($1, $2, $3)",
            &[&provider.as_ref(), &provider_meeting_id, &recording_url],
        )
        .await
    }
}

/// Candidate meeting to process for auto-end checks.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
pub(crate) struct MeetingAutoEndCandidate {
    pub meeting_id: Uuid,
    #[serde(alias = "meeting_provider_id")]
    pub provider: MeetingProvider,
    pub provider_meeting_id: String,
}
