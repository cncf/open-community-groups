//! This module defines types and logic to manage meeting synchronization with providers.

use std::{collections::HashMap, sync::Arc, time::Duration};

use anyhow::Result;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
#[cfg(test)]
use mockall::automock;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use strum::{AsRefStr, Display, EnumString};
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
        providers: DynMeetingsProviders,
        db: DynDB,
        task_tracker: &TaskTracker,
        cancellation_token: &CancellationToken,
    ) -> Self {
        // Setup and run some workers to sync meetings
        for _ in 1..=NUM_WORKERS {
            let mut worker = MeetingsManagerWorker {
                cancellation_token: cancellation_token.clone(),
                db: db.clone(),
                providers: providers.clone(),
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
    /// Providers map for meeting operations.
    providers: DynMeetingsProviders,
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
            // Look up the provider for this meeting
            let provider = self.providers.get(&meeting.provider);

            // Determine action and sync with provider
            let result = match provider {
                Some(provider) => match meeting.sync_action() {
                    SyncAction::Create => self.create_meeting(client_id, &meeting, provider).await,
                    SyncAction::Delete => self.delete_meeting(client_id, &meeting, provider).await,
                    SyncAction::Update => self.update_meeting(client_id, &meeting, provider).await,
                },
                None => Err(SyncError::ProviderNotConfigured(meeting.provider)),
            };

            // Handle errors based on type
            if let Err(err) = result {
                // Non-retryable: record error and mark as synced
                if err.is_non_retryable() {
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
    #[instrument(skip(self, meeting, provider), err)]
    async fn create_meeting(
        &self,
        client_id: Uuid,
        meeting: &Meeting,
        provider: &DynMeetingsProvider,
    ) -> Result<(), SyncError> {
        // Call provider to create meeting
        let provider_meeting = provider.create_meeting(meeting).await?;

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
    #[instrument(skip(self, meeting, provider), err)]
    async fn delete_meeting(
        &self,
        client_id: Uuid,
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
        self.db
            .delete_meeting(client_id, meeting)
            .await
            .map_err(SyncError::Other)?;

        Ok(())
    }

    /// Update a meeting on the provider and mark as synced in database.
    #[instrument(skip(self, meeting, provider), err)]
    async fn update_meeting(
        &self,
        client_id: Uuid,
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
    pub provider: MeetingProvider,

    pub delete: Option<bool>,
    pub duration: Option<Duration>,
    pub event_id: Option<Uuid>,
    pub hosts: Option<Vec<String>>,
    pub join_url: Option<String>,
    pub meeting_id: Option<Uuid>,
    pub password: Option<String>,
    pub provider_meeting_id: Option<String>,
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

#[cfg(test)]
mod tests {
    use std::{collections::HashMap, sync::Arc, time::Duration};

    use anyhow::anyhow;
    use tokio_util::sync::CancellationToken;
    use uuid::Uuid;

    use crate::db::{DynDB, mock::MockDB};

    use super::{
        DynMeetingsProvider, Meeting, MeetingProvider, MeetingProviderError, MeetingProviderMeeting,
        MeetingsManagerWorker, MockMeetingsProvider, SyncAction, SyncError,
    };

    // MeetingProviderError tests.

    #[test]
    fn test_meeting_provider_error_is_retryable_client() {
        let err = MeetingProviderError::Client("invalid input".to_string());
        assert!(!err.is_retryable());
    }

    #[test]
    fn test_meeting_provider_error_is_retryable_network() {
        let err = MeetingProviderError::Network("connection refused".to_string());
        assert!(err.is_retryable());
    }

    #[test]
    fn test_meeting_provider_error_is_retryable_not_found() {
        let err = MeetingProviderError::NotFound;
        assert!(!err.is_retryable());
    }

    #[test]
    fn test_meeting_provider_error_is_retryable_rate_limit() {
        let err = MeetingProviderError::RateLimit {
            retry_after: Duration::from_secs(60),
        };
        assert!(err.is_retryable());
    }

    #[test]
    fn test_meeting_provider_error_is_retryable_server() {
        let err = MeetingProviderError::Server("internal error".to_string());
        assert!(err.is_retryable());
    }

    #[test]
    fn test_meeting_provider_error_is_retryable_token() {
        let err = MeetingProviderError::Token("expired".to_string());
        assert!(err.is_retryable());
    }

    #[test]
    fn test_meeting_provider_error_retry_after_rate_limit() {
        let err = MeetingProviderError::RateLimit {
            retry_after: Duration::from_secs(120),
        };

        // Check retry_after returns the duration
        assert_eq!(err.retry_after(), Some(Duration::from_secs(120)));
    }

    #[test]
    fn test_meeting_provider_error_retry_after_other() {
        // Check retry_after returns None for non-RateLimit errors
        assert_eq!(
            MeetingProviderError::Client("error".to_string()).retry_after(),
            None
        );
        assert_eq!(
            MeetingProviderError::Network("error".to_string()).retry_after(),
            None
        );
        assert_eq!(MeetingProviderError::NotFound.retry_after(), None);
        assert_eq!(
            MeetingProviderError::Server("error".to_string()).retry_after(),
            None
        );
        assert_eq!(
            MeetingProviderError::Token("error".to_string()).retry_after(),
            None
        );
    }

    // Meeting::sync_action tests.

    #[test]
    fn test_meeting_sync_action_create() {
        // Setup meeting without provider_meeting_id
        let meeting = Meeting {
            provider_meeting_id: None,
            delete: None,
            ..Default::default()
        };

        // Check sync action is Create
        assert!(matches!(meeting.sync_action(), SyncAction::Create));
    }

    #[test]
    fn test_meeting_sync_action_delete() {
        // Setup meeting with delete flag
        let meeting = Meeting {
            provider_meeting_id: Some("provider-123".to_string()),
            delete: Some(true),
            ..Default::default()
        };

        // Check sync action is Delete
        assert!(matches!(meeting.sync_action(), SyncAction::Delete));
    }

    #[test]
    fn test_meeting_sync_action_update() {
        // Setup meeting with provider_meeting_id
        let meeting = Meeting {
            provider_meeting_id: Some("provider-123".to_string()),
            delete: None,
            ..Default::default()
        };

        // Check sync action is Update
        assert!(matches!(meeting.sync_action(), SyncAction::Update));
    }

    // MeetingsManagerWorker tests.

    #[tokio::test]
    async fn test_worker_sync_meeting_creates_new_meeting() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();
        let meeting_id = Uuid::new_v4();
        let meeting = Meeting {
            meeting_id: Some(meeting_id),
            provider_meeting_id: None,
            topic: Some("Test Meeting".to_string()),
            ..Default::default()
        };

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_meeting_out_of_sync()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(move |_| Ok(Some(meeting.clone())));
        db.expect_add_meeting()
            .times(1)
            .withf(move |cid, m| {
                *cid == client_id
                    && m.meeting_id == Some(meeting_id)
                    && m.provider_meeting_id == Some("zoom-123".to_string())
                    && m.join_url == Some("https://zoom.us/j/123".to_string())
            })
            .returning(|_, _| Ok(()));
        db.expect_tx_commit()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup meetings provider mock
        let mut mp = MockMeetingsProvider::new();
        mp.expect_create_meeting().times(1).returning(|_| {
            Box::pin(async {
                Ok(MeetingProviderMeeting {
                    id: "zoom-123".to_string(),
                    join_url: "https://zoom.us/j/123".to_string(),
                    password: Some("secret".to_string()),
                })
            })
        });
        let mp: DynMeetingsProvider = Arc::new(mp);

        // Setup worker and sync meeting
        let mut worker = sample_worker(db, mp);
        let synced = worker.sync_meeting().await.unwrap();

        // Check result matches expectations
        assert!(synced);
    }

    #[tokio::test]
    async fn test_worker_sync_meeting_updates_existing_meeting() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();
        let meeting_id = Uuid::new_v4();
        let provider_meeting_id = "zoom-456".to_string();
        let meeting = Meeting {
            meeting_id: Some(meeting_id),
            provider_meeting_id: Some(provider_meeting_id.clone()),
            topic: Some("Updated Meeting".to_string()),
            ..Default::default()
        };

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_meeting_out_of_sync()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(move |_| Ok(Some(meeting.clone())));
        db.expect_update_meeting()
            .times(1)
            .withf(move |cid, m| {
                *cid == client_id
                    && m.meeting_id == Some(meeting_id)
                    && m.join_url == Some("https://zoom.us/j/456".to_string())
            })
            .returning(|_, _| Ok(()));
        db.expect_tx_commit()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup meetings provider mock
        let mut mp = MockMeetingsProvider::new();
        let provider_meeting_id_clone = provider_meeting_id.clone();
        mp.expect_update_meeting()
            .times(1)
            .withf(move |pid, _| *pid == provider_meeting_id_clone)
            .returning(|_, _| Box::pin(async { Ok(()) }));
        mp.expect_get_meeting()
            .times(1)
            .withf(move |pid| *pid == provider_meeting_id)
            .returning(|_| {
                Box::pin(async {
                    Ok(MeetingProviderMeeting {
                        id: "zoom-456".to_string(),
                        join_url: "https://zoom.us/j/456".to_string(),
                        password: Some("newsecret".to_string()),
                    })
                })
            });
        let mp: DynMeetingsProvider = Arc::new(mp);

        // Setup worker and sync meeting
        let mut worker = sample_worker(db, mp);
        let synced = worker.sync_meeting().await.unwrap();

        // Check result matches expectations
        assert!(synced);
    }

    #[tokio::test]
    async fn test_worker_sync_meeting_deletes_meeting() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();
        let meeting_id = Uuid::new_v4();
        let provider_meeting_id = "zoom-789".to_string();
        let meeting = Meeting {
            meeting_id: Some(meeting_id),
            provider_meeting_id: Some(provider_meeting_id.clone()),
            delete: Some(true),
            ..Default::default()
        };

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_meeting_out_of_sync()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(move |_| Ok(Some(meeting.clone())));
        db.expect_delete_meeting()
            .times(1)
            .withf(move |cid, m| *cid == client_id && m.meeting_id == Some(meeting_id))
            .returning(|_, _| Ok(()));
        db.expect_tx_commit()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup meetings provider mock
        let mut mp = MockMeetingsProvider::new();
        mp.expect_delete_meeting()
            .times(1)
            .withf(move |pid| *pid == provider_meeting_id)
            .returning(|_| Box::pin(async { Ok(()) }));
        let mp: DynMeetingsProvider = Arc::new(mp);

        // Setup worker and sync meeting
        let mut worker = sample_worker(db, mp);
        let synced = worker.sync_meeting().await.unwrap();

        // Check result matches expectations
        assert!(synced);
    }

    #[tokio::test]
    async fn test_worker_sync_meeting_delete_not_found_succeeds() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();
        let meeting_id = Uuid::new_v4();
        let provider_meeting_id = "zoom-notfound".to_string();
        let meeting = Meeting {
            meeting_id: Some(meeting_id),
            provider_meeting_id: Some(provider_meeting_id.clone()),
            delete: Some(true),
            ..Default::default()
        };

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_meeting_out_of_sync()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(move |_| Ok(Some(meeting.clone())));
        db.expect_delete_meeting()
            .times(1)
            .withf(move |cid, m| *cid == client_id && m.meeting_id == Some(meeting_id))
            .returning(|_, _| Ok(()));
        db.expect_tx_commit()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup meetings provider mock (returns NotFound)
        let mut mp = MockMeetingsProvider::new();
        mp.expect_delete_meeting()
            .times(1)
            .withf(move |pid| *pid == provider_meeting_id)
            .returning(|_| Box::pin(async { Err(MeetingProviderError::NotFound) }));
        let mp: DynMeetingsProvider = Arc::new(mp);

        // Setup worker and sync meeting
        let mut worker = sample_worker(db, mp);
        let synced = worker.sync_meeting().await.unwrap();

        // Check result matches expectations (NotFound is treated as success)
        assert!(synced);
    }

    #[tokio::test]
    async fn test_worker_sync_meeting_no_pending_meeting() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_meeting_out_of_sync()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(None));
        db.expect_tx_rollback()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup meetings provider mock (should not be called)
        let mut mp = MockMeetingsProvider::new();
        mp.expect_create_meeting().never();
        mp.expect_update_meeting().never();
        mp.expect_delete_meeting().never();
        let mp: DynMeetingsProvider = Arc::new(mp);

        // Setup worker and sync meeting
        let mut worker = sample_worker(db, mp);
        let synced = worker.sync_meeting().await.unwrap();

        // Check result matches expectations
        assert!(!synced);
    }

    #[tokio::test]
    async fn test_worker_sync_meeting_retryable_error_rollback() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();
        let meeting = Meeting {
            meeting_id: Some(Uuid::new_v4()),
            provider_meeting_id: None,
            ..Default::default()
        };

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_meeting_out_of_sync()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(move |_| Ok(Some(meeting.clone())));
        db.expect_tx_rollback()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup meetings provider mock (returns retryable error)
        let mut mp = MockMeetingsProvider::new();
        mp.expect_create_meeting()
            .times(1)
            .returning(|_| Box::pin(async { Err(MeetingProviderError::Network("timeout".to_string())) }));
        let mp: DynMeetingsProvider = Arc::new(mp);

        // Setup worker and sync meeting
        let mut worker = sample_worker(db, mp);
        let result = worker.sync_meeting().await;

        // Check result is a retryable provider error
        assert!(matches!(
            result,
            Err(SyncError::Provider(MeetingProviderError::Network(_)))
        ));
    }

    #[tokio::test]
    async fn test_worker_sync_meeting_non_retryable_error_records_error() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();
        let meeting_id = Uuid::new_v4();
        let meeting = Meeting {
            meeting_id: Some(meeting_id),
            provider_meeting_id: None,
            ..Default::default()
        };

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_meeting_out_of_sync()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(move |_| Ok(Some(meeting.clone())));
        db.expect_set_meeting_error()
            .times(1)
            .withf(move |cid, m, err| {
                *cid == client_id && m.meeting_id == Some(meeting_id) && err.contains("invalid meeting data")
            })
            .returning(|_, _, _| Ok(()));
        db.expect_tx_commit()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup meetings provider mock (returns non-retryable error)
        let mut mp = MockMeetingsProvider::new();
        mp.expect_create_meeting().times(1).returning(|_| {
            Box::pin(async { Err(MeetingProviderError::Client("invalid meeting data".to_string())) })
        });
        let mp: DynMeetingsProvider = Arc::new(mp);

        // Setup worker and sync meeting
        let mut worker = sample_worker(db, mp);
        let synced = worker.sync_meeting().await.unwrap();

        // Check result matches expectations (non-retryable error is recorded)
        assert!(synced);
    }

    #[tokio::test]
    async fn test_worker_sync_meeting_db_error_on_get() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_meeting_out_of_sync()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Err(anyhow!("database connection lost")));
        db.expect_tx_rollback()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup meetings provider mock (should not be called)
        let mut mp = MockMeetingsProvider::new();
        mp.expect_create_meeting().never();
        let mp: DynMeetingsProvider = Arc::new(mp);

        // Setup worker and sync meeting
        let mut worker = sample_worker(db, mp);
        let result = worker.sync_meeting().await;

        // Check result is a database error
        assert!(matches!(result, Err(SyncError::Other(_))));
    }

    #[tokio::test]
    async fn test_worker_sync_meeting_delete_without_provider_id() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();
        let meeting_id = Uuid::new_v4();
        // Meeting marked for deletion but never synced to provider (no provider_meeting_id)
        let meeting = Meeting {
            meeting_id: Some(meeting_id),
            provider_meeting_id: None,
            delete: Some(true),
            ..Default::default()
        };

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_meeting_out_of_sync()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(move |_| Ok(Some(meeting.clone())));
        db.expect_delete_meeting()
            .times(1)
            .withf(move |cid, m| *cid == client_id && m.meeting_id == Some(meeting_id))
            .returning(|_, _| Ok(()));
        db.expect_tx_commit()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup meetings provider mock (should not be called since no provider_meeting_id)
        let mut mp = MockMeetingsProvider::new();
        mp.expect_delete_meeting().never();
        let mp: DynMeetingsProvider = Arc::new(mp);

        // Setup worker and sync meeting
        let mut worker = sample_worker(db, mp);
        let synced = worker.sync_meeting().await.unwrap();

        // Check result matches expectations (delete succeeds without provider call)
        assert!(synced);
    }

    #[tokio::test]
    async fn test_worker_sync_meeting_provider_not_configured() {
        // Setup identifiers and data structures
        let client_id = Uuid::new_v4();
        let meeting_id = Uuid::new_v4();
        let meeting = Meeting {
            meeting_id: Some(meeting_id),
            provider_meeting_id: None,
            ..Default::default()
        };

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_tx_begin().times(1).returning(move || Ok(client_id));
        db.expect_get_meeting_out_of_sync()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(move |_| Ok(Some(meeting.clone())));
        db.expect_set_meeting_error()
            .times(1)
            .withf(move |cid, m, err| {
                *cid == client_id
                    && m.meeting_id == Some(meeting_id)
                    && err.contains("provider not configured")
            })
            .returning(|_, _, _| Ok(()));
        db.expect_tx_commit()
            .times(1)
            .withf(move |cid| *cid == client_id)
            .returning(|_| Ok(()));
        let db: DynDB = Arc::new(db);

        // Setup worker with no providers configured
        let mut worker = sample_worker_no_providers(db);
        let synced = worker.sync_meeting().await.unwrap();

        // Check result matches expectations (error recorded, meeting marked as synced)
        assert!(synced);
    }

    // Helpers.

    /// Create a sample worker with mock dependencies.
    fn sample_worker(db: DynDB, mp: DynMeetingsProvider) -> MeetingsManagerWorker {
        let mut providers = HashMap::new();
        providers.insert(MeetingProvider::Zoom, mp);
        MeetingsManagerWorker {
            cancellation_token: CancellationToken::new(),
            db,
            providers: Arc::new(providers),
        }
    }

    /// Create a sample worker with no providers configured.
    fn sample_worker_no_providers(db: DynDB) -> MeetingsManagerWorker {
        MeetingsManagerWorker {
            cancellation_token: CancellationToken::new(),
            db,
            providers: Arc::new(HashMap::new()),
        }
    }
}
