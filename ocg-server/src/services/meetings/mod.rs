//! This module defines types and logic to manage meeting synchronization with providers.

use std::{sync::Arc, time::Duration};

use anyhow::Result;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
#[cfg(test)]
use mockall::automock;
use serde::Serialize;
use serde_with::skip_serializing_none;
use tokio::time::sleep;
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, instrument};
use uuid::Uuid;

use crate::db::DynDB;

pub(crate) mod zoom;

/// Number of concurrent workers that synchronize meetings.
const NUM_WORKERS: usize = 2;

/// Time to wait after a sync error before retrying.
const PAUSE_ON_ERROR: Duration = Duration::from_secs(30);

/// Time to wait when there are no meetings to sync.
const PAUSE_ON_NONE: Duration = Duration::from_secs(30);

/// Trait that defines the interface for a meetings provider.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait MeetingsProvider {
    /// Create a meeting.
    async fn create_meeting(&self, meeting: &Meeting)
    -> Result<MeetingProviderMeeting, MeetingProviderError>;

    /// Delete a meeting.
    async fn delete_meeting(&self, provider_meeting_id: &str) -> Result<(), MeetingProviderError>;

    /// Get meeting details.
    async fn get_meeting(
        &self,
        provider_meeting_id: &str,
    ) -> Result<MeetingProviderMeeting, MeetingProviderError>;

    /// Update a meeting.
    async fn update_meeting(
        &self,
        provider_meeting_id: &str,
        meeting: &Meeting,
    ) -> Result<(), MeetingProviderError>;
}

/// Shared trait object for a meetings provider.
pub(crate) type DynMeetingsProvider = Arc<dyn MeetingsProvider + Send + Sync>;

/// Meeting details returned by the provider.
#[derive(Clone, Debug)]
pub(crate) struct MeetingProviderMeeting {
    pub id: String,
    pub join_url: String,
    pub password: Option<String>,
}

/// Error type for meetings provider operations.
#[derive(Debug)]
pub(crate) enum MeetingProviderError {
    /// Non-retryable client/validation errors.
    Client(String),
    /// Network or connection errors (retryable).
    Network(String),
    /// Meeting not found (for delete - treat as success).
    NotFound,
    /// Rate limit exceeded (retryable after delay).
    RateLimit { retry_after: Duration },
    /// Server errors (retryable).
    Server(String),
    /// Authentication/token errors (retryable).
    Token(String),
}

impl std::fmt::Display for MeetingProviderError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Client(msg) => write!(f, "provider client error: {msg}"),
            Self::Network(msg) => write!(f, "provider network error: {msg}"),
            Self::NotFound => write!(f, "meeting not found"),
            Self::RateLimit { retry_after } => {
                write!(f, "rate limit exceeded (retry after {}s)", retry_after.as_secs())
            }
            Self::Server(msg) => write!(f, "provider server error: {msg}"),
            Self::Token(msg) => write!(f, "provider token error: {msg}"),
        }
    }
}

impl std::error::Error for MeetingProviderError {}

impl MeetingProviderError {
    /// Returns true if this error should be retried.
    pub(crate) fn is_retryable(&self) -> bool {
        matches!(
            self,
            Self::Network(_) | Self::RateLimit { .. } | Self::Server(_) | Self::Token(_)
        )
    }

    /// Returns the recommended retry delay for rate limit errors.
    pub(crate) fn retry_after(&self) -> Option<Duration> {
        match self {
            Self::RateLimit { retry_after } => Some(*retry_after),
            _ => None,
        }
    }
}

/// Meetings manager implementation.
pub(crate) struct MeetingsManager;

impl MeetingsManager {
    /// Create a new `MeetingsManager`.
    #[allow(clippy::needless_pass_by_value)]
    pub(crate) fn new(
        provider: DynMeetingsProvider,
        db: DynDB,
        task_tracker: &TaskTracker,
        cancellation_token: &CancellationToken,
    ) -> Self {
        // Setup and run some workers to sync meetings
        for _ in 1..=NUM_WORKERS {
            let mut worker = MeetingsManagerWorker {
                cancellation_token: cancellation_token.clone(),
                db: db.clone(),
                provider: provider.clone(),
            };
            task_tracker.spawn(async move {
                worker.run().await;
            });
        }

        Self
    }
}

/// Worker responsible for synchronizing meetings with the provider.
struct MeetingsManagerWorker {
    /// Token to signal worker shutdown.
    cancellation_token: CancellationToken,
    /// Database handle for meeting queries.
    db: DynDB,
    /// Provider for meeting operations.
    provider: DynMeetingsProvider,
}

impl MeetingsManagerWorker {
    /// Main worker loop: synchronizes meetings until cancelled.
    async fn run(&mut self) {
        loop {
            // Try to sync a pending meeting
            match self.sync_meeting().await {
                Ok(true) => {
                    // One meeting was synced, try to sync another one immediately
                }
                Ok(false) => tokio::select! {
                    // No pending meetings to sync, pause unless we've been asked
                    // to stop
                    () = sleep(PAUSE_ON_NONE) => {},
                    () = self.cancellation_token.cancelled() => break,
                },
                Err(err) => {
                    // Something went wrong syncing the meeting, pause unless
                    // we've been asked to stop
                    error!(%err, "error syncing meeting");
                    let pause = err.retry_after().unwrap_or(PAUSE_ON_ERROR);
                    tokio::select! {
                        () = sleep(pause) => {},
                        () = self.cancellation_token.cancelled() => break,
                    }
                }
            }

            // Exit if the worker has been asked to stop
            if self.cancellation_token.is_cancelled() {
                break;
            }
        }
    }

    /// Attempt to sync an out of sync meeting, if any.
    #[instrument(skip(self), err)]
    async fn sync_meeting(&mut self) -> Result<bool, SyncError> {
        // Begin transaction
        let client_id = self.db.tx_begin().await.map_err(SyncError::Other)?;

        // Get out-of-sync meeting
        let meeting = match self.db.get_meeting_out_of_sync(client_id).await {
            Ok(meeting) => meeting,
            Err(err) => {
                let _ = self.db.tx_rollback(client_id).await;
                return Err(SyncError::Other(err));
            }
        };

        // Process meeting if found
        if let Some(meeting) = meeting {
            // Determine action and sync with provider
            let result = match meeting.sync_action() {
                SyncAction::Create => self.create_meeting(client_id, &meeting).await,
                SyncAction::Delete => self.delete_meeting(client_id, &meeting).await,
                SyncAction::Update => self.update_meeting(client_id, &meeting).await,
            };

            // Handle errors based on type
            if let Err(err) = result {
                // Check if this is a non-retryable provider error
                let non_retryable = match &err {
                    SyncError::Provider(provider_err) => !provider_err.is_retryable(),
                    SyncError::Other(_) => false,
                };

                // Non-retryable: record error and mark as synced
                if non_retryable {
                    if let Err(db_err) =
                        self.db.set_meeting_error(client_id, &meeting, &err.to_string()).await
                    {
                        error!(?db_err, "error recording meeting error");
                        let _ = self.db.tx_rollback(client_id).await;
                        return Err(SyncError::Other(anyhow::anyhow!("{err}")));
                    }
                    if let Err(e) = self.db.tx_commit(client_id).await {
                        return Err(SyncError::Other(e));
                    }
                    return Ok(true);
                }

                // Retryable error: rollback so meeting stays out-of-sync for retry
                let _ = self.db.tx_rollback(client_id).await;
                return Err(err);
            }

            // Success - commit transaction
            self.db.tx_commit(client_id).await.map_err(SyncError::Other)?;
            Ok(true)
        } else {
            // No meeting to sync, rollback
            let _ = self.db.tx_rollback(client_id).await;
            Ok(false)
        }
    }

    /// Create a meeting on the provider and update local database.
    #[instrument(skip(self, meeting), err)]
    async fn create_meeting(&self, client_id: Uuid, meeting: &Meeting) -> Result<(), SyncError> {
        // Call provider to create meeting
        let provider_meeting = self.provider.create_meeting(meeting).await?;

        // Update meeting with provider details
        let meeting = Meeting {
            join_url: Some(provider_meeting.join_url),
            password: provider_meeting.password,
            provider_meeting_id: Some(provider_meeting.id),
            ..meeting.clone()
        };

        // Add meeting to database
        self.db
            .add_meeting(client_id, &meeting)
            .await
            .map_err(SyncError::Other)?;

        Ok(())
    }

    /// Delete a meeting from the provider and local database.
    #[instrument(skip(self, meeting), err)]
    async fn delete_meeting(&self, client_id: Uuid, meeting: &Meeting) -> Result<(), SyncError> {
        // Call provider to delete meeting
        if let Some(provider_meeting_id) = &meeting.provider_meeting_id {
            // Attempt to delete; treat "meeting not found" as success (already gone)
            match self.provider.delete_meeting(provider_meeting_id).await {
                Ok(()) | Err(MeetingProviderError::NotFound) => {
                    // NotFound means meeting already deleted externally
                }
                Err(e) => return Err(SyncError::Provider(e)),
            }
        }

        // Remove meeting from database
        self.db
            .delete_meeting(client_id, meeting)
            .await
            .map_err(SyncError::Other)?;

        Ok(())
    }

    /// Update a meeting on the provider and mark as synced in database.
    #[instrument(skip(self, meeting), err)]
    async fn update_meeting(&self, client_id: Uuid, meeting: &Meeting) -> Result<(), SyncError> {
        // Get provider meeting ID
        let provider_meeting_id = meeting
            .provider_meeting_id
            .as_ref()
            .ok_or_else(|| SyncError::Other(anyhow::anyhow!("missing provider_meeting_id for update")))?;

        // Call provider to update meeting
        self.provider.update_meeting(provider_meeting_id, meeting).await?;

        // Fetch updated meeting details from provider (captures auto-generated password)
        let provider_meeting = self.provider.get_meeting(provider_meeting_id).await?;

        // Update meeting with current details from provider
        let meeting = Meeting {
            join_url: Some(provider_meeting.join_url),
            password: provider_meeting.password,
            ..meeting.clone()
        };

        // Update meeting in database
        self.db
            .update_meeting(client_id, &meeting)
            .await
            .map_err(SyncError::Other)?;

        Ok(())
    }
}

/// Represents a meeting to be synced with the provider.
#[skip_serializing_none]
#[derive(Clone, Default, Serialize)]
pub(crate) struct Meeting {
    pub delete: Option<bool>,
    pub duration: Option<Duration>,
    pub event_id: Option<Uuid>,
    pub join_url: Option<String>,
    pub meeting_id: Option<Uuid>,
    pub password: Option<String>,
    pub provider_meeting_id: Option<String>,
    pub requires_password: Option<bool>,
    pub session_id: Option<Uuid>,
    pub starts_at: Option<DateTime<Utc>>,
    pub timezone: Option<String>,
    pub topic: Option<String>,
}

impl Meeting {
    /// Returns the action to take to sync this meeting with the provider.
    pub(crate) fn sync_action(&self) -> SyncAction {
        if self.delete == Some(true) {
            SyncAction::Delete
        } else if self.provider_meeting_id.is_none() {
            SyncAction::Create
        } else {
            SyncAction::Update
        }
    }
}

/// Action to take to sync a meeting with the provider.
pub(crate) enum SyncAction {
    Create,
    Delete,
    Update,
}

/// Error type for meeting sync operations.
#[derive(Debug)]
enum SyncError {
    /// Provider error.
    Provider(MeetingProviderError),
    /// Other errors (DB, parsing, etc).
    Other(anyhow::Error),
}

impl std::fmt::Display for SyncError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Provider(e) => write!(f, "{e}"),
            Self::Other(e) => write!(f, "{e}"),
        }
    }
}

impl From<MeetingProviderError> for SyncError {
    fn from(e: MeetingProviderError) -> Self {
        Self::Provider(e)
    }
}

impl From<anyhow::Error> for SyncError {
    fn from(e: anyhow::Error) -> Self {
        Self::Other(e)
    }
}

impl SyncError {
    /// Returns the retry delay if this is a rate-limited provider error.
    fn retry_after(&self) -> Option<Duration> {
        match self {
            Self::Provider(provider_err) => provider_err.retry_after(),
            Self::Other(_) => None,
        }
    }
}
