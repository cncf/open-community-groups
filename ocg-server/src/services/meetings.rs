//! This module defines types and logic to manage meeting synchronization with providers.

use std::{collections::HashMap, sync::Arc, time::Duration};

use anyhow::Result;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
#[cfg(test)]
use mockall::automock;
use serde::{Deserialize, Serialize};
use serde_with::{DefaultOnNull, DurationSecondsWithFrac, serde_as, skip_serializing_none};
use strum::{AsRefStr, Display, EnumString};
use tokio::time::sleep;
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, instrument};
use uuid::Uuid;

use crate::{config::MeetingsZoomConfig, db::DynDB};

#[cfg(test)]
mod tests;

pub(crate) mod zoom;

/// Time after which claimed meeting processing requires manual review.
const MEETING_PROCESSING_TIMEOUT: Duration = Duration::from_mins(15);

/// Number of concurrent workers that auto-end meetings.
const NUM_AUTO_END_WORKERS: usize = 1;

/// Number of workers that recover stale meeting processing claims.
const NUM_CLAIM_RECOVERY_WORKERS: usize = 1;

/// Number of concurrent workers that synchronize meetings.
const NUM_SYNC_WORKERS: usize = 2;

/// Time to wait after an auto-end error before retrying.
const PAUSE_ON_AUTO_END_ERROR: Duration = Duration::from_secs(30);

/// Time to wait when there are no meetings to auto-end.
const PAUSE_ON_AUTO_END_NONE: Duration = Duration::from_mins(1);

/// Time to wait after a claim recovery error before retrying.
const PAUSE_ON_CLAIM_RECOVERY_ERROR: Duration = Duration::from_secs(30);

/// Time to wait between claim recovery checks.
const PAUSE_ON_CLAIM_RECOVERY_NONE: Duration = Duration::from_mins(1);

/// Time to wait after a sync error before retrying.
const PAUSE_ON_SYNC_ERROR: Duration = Duration::from_secs(30);

/// Time to wait when there are no meetings to sync.
const PAUSE_ON_SYNC_NONE: Duration = Duration::from_secs(30);

/// Trait that defines the interface for a meetings provider.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait MeetingsProvider {
    /// Create a meeting.
    async fn create_meeting(&self, meeting: &Meeting)
    -> Result<MeetingProviderMeeting, MeetingProviderError>;

    /// Delete a meeting.
    async fn delete_meeting(&self, provider_meeting_id: &str) -> Result<(), MeetingProviderError>;

    /// End a meeting.
    async fn end_meeting(&self, provider_meeting_id: &str) -> Result<MeetingEndResult, MeetingProviderError>;

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

/// Shared map of meetings providers keyed by provider type.
pub(crate) type DynMeetingsProviders = Arc<HashMap<MeetingProvider, DynMeetingsProvider>>;

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
    /// No meeting slot is available for automatic creation.
    NoSlotsAvailable,
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
            Self::NoSlotsAvailable => write!(f, "no meeting slots available for automatic creation"),
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
        providers: DynMeetingsProviders,
        db: DynDB,
        zoom_cfg: Option<MeetingsZoomConfig>,
        task_tracker: &TaskTracker,
        cancellation_token: &CancellationToken,
    ) -> Self {
        // Setup and run workers to auto-end overdue meetings
        for _ in 1..=NUM_AUTO_END_WORKERS {
            let mut worker = MeetingsAutoEndWorker {
                cancellation_token: cancellation_token.clone(),
                db: db.clone(),
                providers: providers.clone(),
            };
            task_tracker.spawn(async move {
                worker.run().await;
            });
        }

        // Setup and run workers to recover abandoned meeting processing claims
        for _ in 1..=NUM_CLAIM_RECOVERY_WORKERS {
            let worker = MeetingsClaimRecoveryWorker {
                cancellation_token: cancellation_token.clone(),
                db: db.clone(),
            };
            task_tracker.spawn(async move {
                worker.run().await;
            });
        }

        // Setup and run workers to synchronize meetings
        for _ in 1..=NUM_SYNC_WORKERS {
            let mut worker = MeetingsSyncWorker {
                cancellation_token: cancellation_token.clone(),
                db: db.clone(),
                providers: providers.clone(),
                zoom_cfg: zoom_cfg.clone(),
            };
            task_tracker.spawn(async move {
                worker.run().await;
            });
        }

        Self
    }
}

/// Worker responsible for auto-ending overdue meetings.
struct MeetingsAutoEndWorker {
    /// Token to signal worker shutdown.
    cancellation_token: CancellationToken,
    /// Database handle for meeting queries.
    db: DynDB,
    /// Providers map for meeting operations.
    providers: DynMeetingsProviders,
}

impl MeetingsAutoEndWorker {
    /// Main worker loop: auto-ends meetings until cancelled.
    async fn run(&mut self) {
        loop {
            // Try to auto-end an overdue meeting
            match self.auto_end_meeting().await {
                Ok(true) => {
                    // One meeting was processed, try to process another one immediately
                }
                Ok(false) => tokio::select! {
                    // No overdue meetings to process, pause unless we've been asked to stop
                    () = sleep(PAUSE_ON_AUTO_END_NONE) => {},
                    () = self.cancellation_token.cancelled() => break,
                },
                Err(err) => {
                    // Something went wrong processing auto-end, pause unless we've been asked to stop
                    error!(%err, "error auto-ending meeting");
                    let pause = err.retry_after().unwrap_or(PAUSE_ON_AUTO_END_ERROR);
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

    /// Attempt to auto-end one overdue meeting, if any.
    #[instrument(skip(self), err)]
    async fn auto_end_meeting(&self) -> Result<bool, SyncError> {
        // Claim an overdue meeting candidate before provider side effects
        let Some(candidate) = self.db.claim_meeting_for_auto_end().await.map_err(SyncError::Other)? else {
            return Ok(false);
        };

        // Ensure this meeting provider is configured and supported at runtime
        let Some(provider) = self.providers.get(&candidate.provider) else {
            error!(
                meeting_id = %candidate.meeting_id,
                provider = %candidate.provider,
                "provider not configured for auto-end, recording error outcome",
            );

            self.db
                .set_meeting_auto_end_check_outcome(candidate.meeting_id, MeetingAutoEndCheckOutcome::Error)
                .await
                .map_err(SyncError::Other)?;
            return Ok(true);
        };

        // End meeting and map provider outcome to a stored check outcome
        let check_outcome = match provider.end_meeting(&candidate.provider_meeting_id).await {
            Ok(MeetingEndResult::AlreadyNotRunning) => MeetingAutoEndCheckOutcome::AlreadyNotRunning,
            Ok(MeetingEndResult::Ended) => MeetingAutoEndCheckOutcome::AutoEnded,
            Err(MeetingProviderError::NotFound) => MeetingAutoEndCheckOutcome::NotFound,
            Err(err) if err.is_retryable() => {
                self.db
                    .release_meeting_auto_end_check_claim(candidate.meeting_id)
                    .await
                    .map_err(SyncError::Other)?;
                return Err(SyncError::Provider(err));
            }
            Err(err) => {
                error!(
                    %err,
                    meeting_id = %candidate.meeting_id,
                    provider_meeting_id = %candidate.provider_meeting_id,
                    "non-retryable auto-end error, recording error outcome",
                );
                MeetingAutoEndCheckOutcome::Error
            }
        };

        // Persist check outcome to avoid reprocessing the same meeting
        self.db
            .set_meeting_auto_end_check_outcome(candidate.meeting_id, check_outcome)
            .await
            .map_err(SyncError::Other)?;

        Ok(true)
    }
}

/// Worker responsible for marking abandoned meeting processing claims.
struct MeetingsClaimRecoveryWorker {
    /// Token to signal worker shutdown.
    cancellation_token: CancellationToken,
    /// Database handle for meeting queries.
    db: DynDB,
}

impl MeetingsClaimRecoveryWorker {
    /// Main worker loop: recovers stale meeting claims until cancelled.
    async fn run(&self) {
        loop {
            // Recover stale meeting claims and pick next pause interval
            let pause = match self.mark_stale_meeting_claims_unknown().await {
                Ok(_) => PAUSE_ON_CLAIM_RECOVERY_NONE,
                Err(err) => {
                    error!(%err, "error recovering stale meeting claims");
                    PAUSE_ON_CLAIM_RECOVERY_ERROR
                }
            };

            // Exit if the worker has been asked to stop
            tokio::select! {
                () = sleep(pause) => {},
                () = self.cancellation_token.cancelled() => break,
            }
        }
    }

    /// Mark stale meeting processing claims with an unknown outcome.
    #[instrument(skip(self), err)]
    async fn mark_stale_meeting_claims_unknown(&self) -> Result<usize> {
        let auto_end_count = self
            .db
            .mark_stale_meeting_auto_end_checks_unknown(MEETING_PROCESSING_TIMEOUT)
            .await?;
        let sync_count = self
            .db
            .mark_stale_meeting_syncs_unknown(MEETING_PROCESSING_TIMEOUT)
            .await?;

        Ok(auto_end_count + sync_count)
    }
}

/// Worker responsible for synchronizing meetings with the provider.
struct MeetingsSyncWorker {
    /// Token to signal worker shutdown.
    cancellation_token: CancellationToken,
    /// Database handle for meeting queries.
    db: DynDB,
    /// Providers map for meeting operations.
    providers: DynMeetingsProviders,
    /// Zoom configuration.
    zoom_cfg: Option<MeetingsZoomConfig>,
}

impl MeetingsSyncWorker {
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
                    () = sleep(PAUSE_ON_SYNC_NONE) => {},
                    () = self.cancellation_token.cancelled() => break,
                },
                Err(err) => {
                    // Something went wrong syncing the meeting, pause unless
                    // we've been asked to stop
                    error!(%err, "error syncing meeting");
                    let pause = err.retry_after().unwrap_or(PAUSE_ON_SYNC_ERROR);
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

    /// Attempt to sync an out-of-sync meeting, if any.
    #[instrument(skip(self), err)]
    async fn sync_meeting(&mut self) -> Result<bool, SyncError> {
        // Claim an out-of-sync meeting before provider side effects
        let Some(meeting) = self.db.claim_meeting_out_of_sync().await.map_err(SyncError::Other)? else {
            return Ok(false);
        };

        // Look up the provider for this meeting
        let provider = self.providers.get(&meeting.provider);

        // Determine action and sync with provider
        let result = match provider {
            Some(provider) => match meeting.sync_action() {
                SyncAction::Create => self.create_meeting(&meeting, provider).await,
                SyncAction::Delete => self.delete_meeting(&meeting, provider).await,
                SyncAction::Update => self.update_meeting(&meeting, provider).await,
            },
            None => Err(SyncError::ProviderNotConfigured(meeting.provider)),
        };

        // Handle errors based on type
        if let Err(err) = result {
            // Non-retryable: record error and mark as synced
            if err.is_non_retryable() {
                self.db
                    .set_meeting_error(&meeting, &err.to_string())
                    .await
                    .map_err(SyncError::Other)?;
                return Ok(true);
            }

            // Retryable error: release the claim so the meeting can be retried
            self.db
                .release_meeting_sync_claim(&meeting)
                .await
                .map_err(SyncError::Other)?;
            return Err(err);
        }

        Ok(true)
    }

    /// Create a meeting on the provider and update local database.
    #[instrument(skip(self, meeting, provider), err)]
    async fn create_meeting(
        &self,
        meeting: &Meeting,
        provider: &DynMeetingsProvider,
    ) -> Result<(), SyncError> {
        // Assign provider host user ID when needed before creating the provider meeting
        let meeting = self.assign_provider_host_user(meeting).await?;

        // Call provider to create meeting
        let provider_meeting = provider.create_meeting(&meeting).await?;

        // Update meeting with provider details
        let meeting = Meeting {
            join_url: Some(provider_meeting.join_url),
            password: provider_meeting.password,
            provider_meeting_id: Some(provider_meeting.id),
            ..meeting
        };

        // Add meeting to database
        self.db.add_meeting(&meeting).await.map_err(SyncError::Other)?;

        Ok(())
    }

    /// Delete a meeting from the provider and local database.
    #[instrument(skip(self, meeting, provider), err)]
    async fn delete_meeting(
        &self,
        meeting: &Meeting,
        provider: &DynMeetingsProvider,
    ) -> Result<(), SyncError> {
        // Call provider to delete meeting
        if let Some(provider_meeting_id) = &meeting.provider_meeting_id {
            // Attempt to delete; treat "meeting not found" as success (already gone)
            match provider.delete_meeting(provider_meeting_id).await {
                Ok(()) | Err(MeetingProviderError::NotFound) => {
                    // NotFound means meeting already deleted externally
                }
                Err(e) => return Err(SyncError::Provider(e)),
            }
        }

        // Remove meeting from database
        self.db.delete_meeting(meeting).await.map_err(SyncError::Other)?;

        Ok(())
    }

    /// Update a meeting on the provider and mark as synced in database.
    #[instrument(skip(self, meeting, provider), err)]
    async fn update_meeting(
        &self,
        meeting: &Meeting,
        provider: &DynMeetingsProvider,
    ) -> Result<(), SyncError> {
        // Get provider meeting ID
        let provider_meeting_id = meeting
            .provider_meeting_id
            .as_ref()
            .ok_or_else(|| SyncError::Other(anyhow::anyhow!("missing provider_meeting_id for update")))?;

        // Call provider to update meeting
        provider.update_meeting(provider_meeting_id, meeting).await?;

        // Fetch updated meeting details from provider (captures auto-generated password)
        let provider_meeting = provider.get_meeting(provider_meeting_id).await?;

        // Update meeting with current details from provider
        let meeting = Meeting {
            join_url: Some(provider_meeting.join_url),
            password: provider_meeting.password,
            ..meeting.clone()
        };

        // Update meeting in database
        self.db.update_meeting(&meeting).await.map_err(SyncError::Other)?;

        Ok(())
    }

    /// Assign provider-specific host user information before meeting creation.
    async fn assign_provider_host_user(&self, meeting: &Meeting) -> Result<Meeting, SyncError> {
        match meeting.provider {
            MeetingProvider::Zoom => self.assign_zoom_host_user(meeting).await,
        }
    }

    /// Assign a Zoom host user from the configured pool based on overlapping load.
    async fn assign_zoom_host_user(&self, meeting: &Meeting) -> Result<Meeting, SyncError> {
        if meeting.provider_host_user_id.is_some() {
            return Ok(meeting.clone());
        }

        // Ensure Zoom configuration is available
        let zoom_cfg = self
            .zoom_cfg
            .as_ref()
            .ok_or(SyncError::ProviderNotConfigured(MeetingProvider::Zoom))?;

        // Ensure meeting has necessary timing information for slot allocation
        let starts_at = meeting.starts_at.ok_or_else(|| {
            SyncError::Provider(MeetingProviderError::Client(
                "missing meeting starts_at".to_string(),
            ))
        })?;
        let ends_at = meeting.ends_at().ok_or_else(|| {
            SyncError::Provider(MeetingProviderError::Client(
                "missing meeting duration".to_string(),
            ))
        })?;

        // Query database for an available host user with capacity for this meeting's time slot
        let provider_host_user_id = self
            .db
            .assign_zoom_host_user(
                meeting,
                &zoom_cfg.host_pool_users,
                zoom_cfg.max_simultaneous_meetings_per_host,
                starts_at,
                ends_at,
            )
            .await
            .map_err(SyncError::Other)?;

        // No host user available, cannot create meeting
        let Some(provider_host_user_id) = provider_host_user_id else {
            return Err(SyncError::Provider(MeetingProviderError::NoSlotsAvailable));
        };

        Ok(Meeting {
            provider_host_user_id: Some(provider_host_user_id),
            ..meeting.clone()
        })
    }
}

/// Represents a meeting to be synced with the provider.
#[skip_serializing_none]
#[serde_as]
#[derive(Clone, Default, Deserialize, Serialize)]
pub(crate) struct Meeting {
    #[serde(alias = "meeting_provider_id", default)]
    #[serde_as(deserialize_as = "DefaultOnNull")]
    pub provider: MeetingProvider,

    pub delete: Option<bool>,
    #[serde(alias = "duration_secs")]
    #[serde_as(deserialize_as = "Option<DurationSecondsWithFrac<f64>>")]
    pub duration: Option<Duration>,
    pub event_id: Option<Uuid>,
    pub hosts: Option<Vec<String>>,
    pub join_url: Option<String>,
    pub meeting_id: Option<Uuid>,
    pub password: Option<String>,
    pub provider_host_user_id: Option<String>,
    pub provider_meeting_id: Option<String>,
    pub session_id: Option<Uuid>,
    pub starts_at: Option<DateTime<Utc>>,
    #[serde(skip_serializing)]
    pub sync_claimed_at: Option<DateTime<Utc>>,
    #[serde(skip_serializing)]
    pub sync_state_hash: Option<String>,
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

    /// Returns the end timestamp.
    fn ends_at(&self) -> Option<DateTime<Utc>> {
        let starts_at = self.starts_at?;
        let duration = self.duration?;
        let duration = chrono::Duration::from_std(duration).ok()?;

        starts_at.checked_add_signed(duration)
    }
}

/// Meeting provider options.
#[derive(
    AsRefStr, Clone, Copy, Debug, Default, Deserialize, Display, EnumString, Eq, Hash, PartialEq, Serialize,
)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub(crate) enum MeetingProvider {
    #[default]
    Zoom,
}

/// Outcome stored after checking an overdue meeting for automatic ending.
#[derive(AsRefStr, Clone, Copy, Debug, Display, EnumString, Eq, PartialEq)]
#[strum(serialize_all = "snake_case")]
pub(crate) enum MeetingAutoEndCheckOutcome {
    AlreadyNotRunning,
    AutoEnded,
    Error,
    NotFound,
}

/// Result returned by providers when trying to end a meeting.
pub(crate) enum MeetingEndResult {
    AlreadyNotRunning,
    Ended,
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
    /// Provider not configured.
    ProviderNotConfigured(MeetingProvider),
    /// Other errors (DB, parsing, etc).
    Other(anyhow::Error),
}

impl std::fmt::Display for SyncError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Provider(e) => write!(f, "{e}"),
            Self::ProviderNotConfigured(p) => write!(f, "provider not configured: {p}"),
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
    /// Returns true if this error should not be retried.
    fn is_non_retryable(&self) -> bool {
        match self {
            Self::Provider(provider_err) => !provider_err.is_retryable(),
            Self::ProviderNotConfigured(_) => true,
            Self::Other(_) => false,
        }
    }

    /// Returns the retry delay if this is a rate-limited provider error.
    fn retry_after(&self) -> Option<Duration> {
        match self {
            Self::Provider(provider_err) => provider_err.retry_after(),
            Self::ProviderNotConfigured(_) | Self::Other(_) => None,
        }
    }
}
