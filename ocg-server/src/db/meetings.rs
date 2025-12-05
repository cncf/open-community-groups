//! This module defines database functionality used to manage meeting synchronization.

use std::{sync::Arc, time::Duration};

use anyhow::{Result, bail};
use async_trait::async_trait;
use chrono::DateTime;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    PgDB,
    db::TX_CLIENT_NOT_FOUND,
    services::meetings::{Meeting, MeetingProvider},
};

/// Trait that defines database operations used to manage meetings.
#[async_trait]
pub(crate) trait DBMeetings {
    /// Adds a new meeting.
    async fn add_meeting(&self, client_id: Uuid, meeting: &Meeting) -> Result<()>;

    /// Deletes a meeting.
    async fn delete_meeting(&self, client_id: Uuid, meeting: &Meeting) -> Result<()>;

    /// Retrieves a meeting that is out of sync.
    async fn get_meeting_out_of_sync(&self, client_id: Uuid) -> Result<Option<Meeting>>;

    /// Records an error for a meeting and marks it as synced.
    async fn set_meeting_error(&self, client_id: Uuid, meeting: &Meeting, error: &str) -> Result<()>;

    /// Updates meeting details and marks it as synced.
    async fn update_meeting(&self, client_id: Uuid, meeting: &Meeting) -> Result<()>;

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
    async fn add_meeting(&self, client_id: Uuid, meeting: &Meeting) -> Result<()> {
        trace!("db: add meeting");

        // Get transaction client
        let tx = {
            let clients = self.txs_clients.read().await;
            let Some((tx, _)) = clients.get(&client_id) else {
                bail!(TX_CLIENT_NOT_FOUND);
            };
            Arc::clone(tx)
        };

        // Add meeting
        tx.execute(
            "select add_meeting($1, $2, $3, $4, $5, $6)",
            &[
                &meeting.provider.as_ref(),
                &meeting.provider_meeting_id,
                &meeting.join_url,
                &meeting.password,
                &meeting.event_id,
                &meeting.session_id,
            ],
        )
        .await?;

        Ok(())
    }

    #[instrument(skip(self, meeting), err)]
    async fn delete_meeting(&self, client_id: Uuid, meeting: &Meeting) -> Result<()> {
        trace!("db: delete meeting");

        // Get transaction client
        let tx = {
            let clients = self.txs_clients.read().await;
            let Some((tx, _)) = clients.get(&client_id) else {
                bail!(TX_CLIENT_NOT_FOUND);
            };
            Arc::clone(tx)
        };

        // Delete meeting
        tx.execute(
            "select delete_meeting($1, $2, $3)",
            &[&meeting.meeting_id, &meeting.event_id, &meeting.session_id],
        )
        .await?;

        Ok(())
    }

    #[instrument(skip(self), err)]
    async fn get_meeting_out_of_sync(&self, client_id: Uuid) -> Result<Option<Meeting>> {
        trace!("db: get meeting out of sync");

        // Get transaction client
        let tx = {
            let clients = self.txs_clients.read().await;
            let Some((tx, _)) = clients.get(&client_id) else {
                bail!(TX_CLIENT_NOT_FOUND);
            };
            Arc::clone(tx)
        };

        // Get out of sync meeting (if any)
        let Some(row) = tx.query_opt("select * from get_meeting_out_of_sync()", &[]).await? else {
            return Ok(None);
        };

        // Convert duration_secs (f64) to std::time::Duration
        let duration = row
            .get::<_, Option<f64>>("duration_secs")
            .map(Duration::from_secs_f64);

        // Convert time::OffsetDateTime to chrono::DateTime<Utc>
        let starts_at = row
            .get::<_, Option<time::OffsetDateTime>>("starts_at")
            .and_then(|t| DateTime::from_timestamp(t.unix_timestamp(), t.nanosecond()));

        // Build meeting
        let meeting = Meeting {
            delete: row.get("delete"),
            duration,
            event_id: row.get("event_id"),
            join_url: row.get("join_url"),
            meeting_id: row.get("meeting_id"),
            password: row.get("password"),
            provider: row
                .get::<_, Option<String>>("meeting_provider_id")
                .and_then(|s| s.parse().ok())
                .unwrap_or_default(),
            provider_meeting_id: row.get("provider_meeting_id"),
            requires_password: row.get("requires_password"),
            session_id: row.get("session_id"),
            starts_at,
            timezone: row.get("timezone"),
            topic: row.get("topic"),
        };

        Ok(Some(meeting))
    }

    #[instrument(skip(self, meeting), err)]
    async fn set_meeting_error(&self, client_id: Uuid, meeting: &Meeting, error: &str) -> Result<()> {
        trace!("db: set meeting error");

        // Get transaction client
        let tx = {
            let clients = self.txs_clients.read().await;
            let Some((tx, _)) = clients.get(&client_id) else {
                bail!(TX_CLIENT_NOT_FOUND);
            };
            Arc::clone(tx)
        };

        // Update meeting error and mark as synced
        if let Some(event_id) = meeting.event_id {
            tx.execute(
                "update event set meeting_error = $1, meeting_in_sync = true where event_id = $2",
                &[&error, &event_id],
            )
            .await?;
        } else if let Some(session_id) = meeting.session_id {
            tx.execute(
                "update session set meeting_error = $1, meeting_in_sync = true where session_id = $2",
                &[&error, &session_id],
            )
            .await?;
        } else if let Some(meeting_id) = meeting.meeting_id {
            // Orphan meeting: no event/session to record error on, delete the row
            tx.execute("delete from meeting where meeting_id = $1", &[&meeting_id])
                .await?;
        }

        Ok(())
    }

    #[instrument(skip(self, meeting), err)]
    async fn update_meeting(&self, client_id: Uuid, meeting: &Meeting) -> Result<()> {
        trace!("db: update meeting");

        // Get transaction client
        let tx = {
            let clients = self.txs_clients.read().await;
            let Some((tx, _)) = clients.get(&client_id) else {
                bail!(TX_CLIENT_NOT_FOUND);
            };
            Arc::clone(tx)
        };

        // Update meeting
        tx.execute(
            "select update_meeting($1, $2, $3, $4, $5, $6)",
            &[
                &meeting.meeting_id,
                &meeting.provider_meeting_id,
                &meeting.join_url,
                &meeting.password,
                &meeting.event_id,
                &meeting.session_id,
            ],
        )
        .await?;

        Ok(())
    }

    #[instrument(skip(self), err)]
    async fn update_meeting_recording_url(
        &self,
        provider: MeetingProvider,
        provider_meeting_id: &str,
        recording_url: &str,
    ) -> Result<()> {
        trace!("db: update meeting recording url");

        let db = self.pool.get().await?;
        db.execute(
            "select update_meeting_recording_url($1, $2, $3)",
            &[&provider.as_ref(), &provider_meeting_id, &recording_url],
        )
        .await?;

        Ok(())
    }
}
