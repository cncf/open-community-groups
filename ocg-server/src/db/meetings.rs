//! This module defines database functionality used to manage meeting synchronization.

use std::{sync::Arc, time::Duration};

use anyhow::{Result, bail};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
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

    /// Finds an available Zoom host user for a meeting time window.
    async fn get_available_zoom_host_user(
        &self,
        client_id: Uuid,
        pool_users: &[String],
        max_simultaneous_meetings_per_user: i32,
        starts_at: DateTime<Utc>,
        ends_at: DateTime<Utc>,
    ) -> Result<Option<String>>;

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
            "select add_meeting($1, $2, $3, $4, $5, $6, $7)",
            &[
                &meeting.provider.as_ref(),
                &meeting.provider_meeting_id,
                &meeting.provider_host_user_id,
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

    #[instrument(skip(self, pool_users), err)]
    async fn get_available_zoom_host_user(
        &self,
        client_id: Uuid,
        pool_users: &[String],
        max_simultaneous_meetings_per_user: i32,
        starts_at: DateTime<Utc>,
        ends_at: DateTime<Utc>,
    ) -> Result<Option<String>> {
        trace!("db: get available zoom host user");

        // Get transaction client
        let tx = {
            let clients = self.txs_clients.read().await;
            let Some((tx, _)) = clients.get(&client_id) else {
                bail!(TX_CLIENT_NOT_FOUND);
            };
            Arc::clone(tx)
        };

        // Find one host user with available slots
        let row = tx
            .query_one(
                "select get_available_zoom_host_user($1::text[], $2::int4, $3::timestamptz, $4::timestamptz)",
                &[
                    &pool_users,
                    &max_simultaneous_meetings_per_user,
                    &starts_at,
                    &ends_at,
                ],
            )
            .await?;

        Ok(row.get("get_available_zoom_host_user"))
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

        // Build meeting
        let meeting = Meeting {
            delete: row.get("delete"),
            duration,
            event_id: row.get("event_id"),
            hosts: row.get("hosts"),
            join_url: row.get("join_url"),
            meeting_id: row.get("meeting_id"),
            password: row.get("password"),
            provider: row
                .get::<_, Option<String>>("meeting_provider_id")
                .and_then(|s| s.parse().ok())
                .unwrap_or_default(),
            provider_host_user_id: None,
            provider_meeting_id: row.get("provider_meeting_id"),
            session_id: row.get("session_id"),
            starts_at: row.get("starts_at"),
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

        // Update meeting error and mark the target as synced
        tx.execute(
            "select set_meeting_error($1::text, $2::uuid, $3::uuid, $4::uuid)",
            &[
                &error,
                &meeting.event_id,
                &meeting.meeting_id,
                &meeting.session_id,
            ],
        )
        .await?;

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
