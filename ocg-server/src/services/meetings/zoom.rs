//! Zoom-backed meetings manager implementation.

use std::time::Duration;

use anyhow::{Result, anyhow};
use reqwest::Client as HttpClient;
use tokio::time::sleep;
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, instrument};
use uuid::Uuid;

use crate::{config::MeetingsZoomConfig, db::DynDB};

use super::{
    Meeting, SyncAction,
    zoom_api::{CreateMeetingRequest, UpdateMeetingRequest, ZoomApi, ZoomApiError},
};

/// Timeout for HTTP requests to Zoom API.
const HTTP_TIMEOUT: Duration = Duration::from_secs(20);

/// Number of concurrent workers that synchronize meetings.
const NUM_WORKERS: usize = 2;

/// Time to wait after a sync error before retrying.
const PAUSE_ON_ERROR: Duration = Duration::from_secs(30);

/// Time to wait when there are no meetings to sync.
const PAUSE_ON_NONE: Duration = Duration::from_secs(30);

/// Zoom-backed meetings manager implementation.
pub(crate) struct ZoomMeetingsManager;

impl ZoomMeetingsManager {
    /// Create a new `ZoomMeetingsManager`.
    #[allow(clippy::needless_pass_by_value)]
    pub(crate) fn new(
        cfg: &MeetingsZoomConfig,
        db: DynDB,
        task_tracker: &TaskTracker,
        cancellation_token: &CancellationToken,
    ) -> Self {
        // Create a shared HTTP client for API calls
        let http_client = HttpClient::builder()
            .timeout(HTTP_TIMEOUT)
            .build()
            .expect("failed to build http client");

        // Setup and run some workers to sync meetings
        for _ in 1..=NUM_WORKERS {
            let mut worker = Worker {
                api: ZoomApi::new(cfg.clone(), http_client.clone()),
                cancellation_token: cancellation_token.clone(),
                db: db.clone(),
            };
            task_tracker.spawn(async move {
                worker.run().await;
            });
        }

        Self
    }
}

/// Worker responsible for synchronizing meetings with the provider.
struct Worker {
    /// Zoom API client for meeting operations.
    api: ZoomApi,
    /// Token to signal worker shutdown.
    cancellation_token: CancellationToken,
    /// Database handle for meeting queries.
    db: DynDB,
}

impl Worker {
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
                // Check if this is a non-retryable API error
                let non_retryable = match &err {
                    SyncError::Api(api_err) => !api_err.is_retryable(),
                    SyncError::Other(_) => false,
                };

                // Non-retryable: record error and mark as synced
                if non_retryable {
                    if let Err(db_err) =
                        self.db.set_meeting_error(client_id, &meeting, &err.to_string()).await
                    {
                        error!(?db_err, "error recording meeting error");
                        let _ = self.db.tx_rollback(client_id).await;
                        return Err(SyncError::Other(anyhow!("{err}")));
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
        // Call Zoom API to create meeting
        let req = CreateMeetingRequest::try_from(meeting)?;
        let zoom_meeting = self.api.create_meeting(&req).await?;

        // Update meeting with provider details (including password from Zoom response)
        let meeting = Meeting {
            password: zoom_meeting.password,
            provider_meeting_id: Some(zoom_meeting.id.to_string()),
            url: Some(zoom_meeting.join_url),
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
        // Call Zoom API to delete meeting
        if let Some(provider_meeting_id_str) = &meeting.provider_meeting_id {
            let provider_meeting_id: i64 = provider_meeting_id_str
                .parse()
                .map_err(|e: std::num::ParseIntError| SyncError::Other(e.into()))?;
            self.api.delete_meeting(provider_meeting_id).await?;
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
        // Parse provider meeting ID
        let provider_meeting_id: i64 = meeting
            .provider_meeting_id
            .as_ref()
            .ok_or_else(|| SyncError::Other(anyhow!("missing provider_meeting_id for update")))?
            .parse()
            .map_err(|e: std::num::ParseIntError| SyncError::Other(e.into()))?;

        // Call Zoom API to update meeting
        let req = UpdateMeetingRequest::try_from(meeting)?;
        self.api.update_meeting(provider_meeting_id, &req).await?;

        // Update meeting in database
        self.db
            .update_meeting(client_id, meeting)
            .await
            .map_err(SyncError::Other)?;

        Ok(())
    }
}

/// Error type for meeting sync operations.
#[derive(Debug)]
enum SyncError {
    /// API error from Zoom.
    Api(ZoomApiError),
    /// Other errors (DB, parsing, etc).
    Other(anyhow::Error),
}

impl std::fmt::Display for SyncError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Api(e) => write!(f, "{e}"),
            Self::Other(e) => write!(f, "{e}"),
        }
    }
}

impl From<ZoomApiError> for SyncError {
    fn from(e: ZoomApiError) -> Self {
        Self::Api(e)
    }
}

impl From<anyhow::Error> for SyncError {
    fn from(e: anyhow::Error) -> Self {
        Self::Other(e)
    }
}

impl SyncError {
    /// Returns the retry delay if this is a rate-limited API error.
    fn retry_after(&self) -> Option<Duration> {
        match self {
            Self::Api(api_err) => api_err.retry_after(),
            Self::Other(_) => None,
        }
    }
}
