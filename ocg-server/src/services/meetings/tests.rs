use std::{collections::HashMap, sync::Arc, time::Duration};

use anyhow::anyhow;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    config::MeetingsZoomConfig,
    db::{DynDB, mock::MockDB},
};

use super::{
    DynMeetingsProvider, Meeting, MeetingAutoEndCheckOutcome, MeetingEndResult, MeetingProvider,
    MeetingProviderError, MeetingProviderMeeting, MeetingsAutoEndWorker, MeetingsClaimRecoveryWorker,
    MeetingsSyncWorker, MockMeetingsProvider, SyncAction, SyncError,
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
fn test_meeting_provider_error_is_retryable_no_slots_available() {
    let err = MeetingProviderError::NoSlotsAvailable;
    assert!(!err.is_retryable());
}

#[test]
fn test_meeting_provider_error_is_retryable_rate_limit() {
    let err = MeetingProviderError::RateLimit {
        retry_after: Duration::from_mins(1),
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
        retry_after: Duration::from_mins(2),
    };

    // Check retry_after returns the duration
    assert_eq!(err.retry_after(), Some(Duration::from_mins(2)));
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

// Meetings workers tests.

#[tokio::test]
async fn test_worker_auto_end_meeting_auto_ended() {
    // Setup identifiers and data structures
    let meeting_id = Uuid::new_v4();
    let provider_meeting_id = "987654321".to_string();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_for_auto_end().times(1).returning(move || {
        Ok(Some(crate::db::meetings::MeetingAutoEndCandidate {
            meeting_id,
            provider: MeetingProvider::Zoom,
            provider_meeting_id: provider_meeting_id.clone(),
        }))
    });
    db.expect_set_meeting_auto_end_check_outcome()
        .times(1)
        .withf(move |mid, outcome| *mid == meeting_id && *outcome == MeetingAutoEndCheckOutcome::AutoEnded)
        .returning(|_, _| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup meetings provider mock
    let mut mp = MockMeetingsProvider::new();
    mp.expect_end_meeting()
        .times(1)
        .returning(|_| Box::pin(async { Ok(MeetingEndResult::Ended) }));
    let mp: DynMeetingsProvider = Arc::new(mp);

    // Setup worker and auto-end meeting
    let worker = sample_auto_end_worker(db, mp);
    let processed = worker.auto_end_meeting().await.unwrap();

    // Check result matches expectations
    assert!(processed);
}

#[tokio::test]
async fn test_worker_auto_end_meeting_not_found_records_not_found_outcome() {
    // Setup identifiers and data structures
    let meeting_id = Uuid::new_v4();
    let provider_meeting_id = "404404404".to_string();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_for_auto_end().times(1).returning(move || {
        Ok(Some(crate::db::meetings::MeetingAutoEndCandidate {
            meeting_id,
            provider: MeetingProvider::Zoom,
            provider_meeting_id: provider_meeting_id.clone(),
        }))
    });
    db.expect_set_meeting_auto_end_check_outcome()
        .times(1)
        .withf(move |mid, outcome| *mid == meeting_id && *outcome == MeetingAutoEndCheckOutcome::NotFound)
        .returning(|_, _| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup meetings provider mock
    let mut mp = MockMeetingsProvider::new();
    mp.expect_end_meeting()
        .times(1)
        .returning(|_| Box::pin(async { Err(MeetingProviderError::NotFound) }));
    let mp: DynMeetingsProvider = Arc::new(mp);

    // Setup worker and auto-end meeting
    let worker = sample_auto_end_worker(db, mp);
    let processed = worker.auto_end_meeting().await.unwrap();

    // Check result matches expectations
    assert!(processed);
}

#[tokio::test]
async fn test_worker_auto_end_meeting_no_pending_meeting() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_for_auto_end().times(1).returning(|| Ok(None));
    let db: DynDB = Arc::new(db);

    // Setup meetings provider mock
    let mut mp = MockMeetingsProvider::new();
    mp.expect_end_meeting().never();
    let mp: DynMeetingsProvider = Arc::new(mp);

    // Setup worker and auto-end meeting
    let worker = sample_auto_end_worker(db, mp);
    let processed = worker.auto_end_meeting().await.unwrap();

    // Check result matches expectations
    assert!(!processed);
}

#[tokio::test]
async fn test_worker_auto_end_meeting_provider_not_configured_records_error_outcome() {
    // Setup identifiers and data structures
    let meeting_id = Uuid::new_v4();
    let provider_meeting_id = "777777777".to_string();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_for_auto_end().times(1).returning(move || {
        Ok(Some(crate::db::meetings::MeetingAutoEndCandidate {
            meeting_id,
            provider: MeetingProvider::Zoom,
            provider_meeting_id: provider_meeting_id.clone(),
        }))
    });
    db.expect_set_meeting_auto_end_check_outcome()
        .times(1)
        .withf(move |mid, outcome| *mid == meeting_id && *outcome == MeetingAutoEndCheckOutcome::Error)
        .returning(|_, _| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup worker with no providers configured
    let worker = sample_auto_end_worker_no_providers(db);
    let processed = worker.auto_end_meeting().await.unwrap();

    // Check result matches expectations
    assert!(processed);
}

#[tokio::test]
async fn test_worker_auto_end_meeting_retryable_error_releases_claim() {
    // Setup identifiers and data structures
    let meeting_id = Uuid::new_v4();
    let provider_meeting_id = "502502502".to_string();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_for_auto_end().times(1).returning(move || {
        Ok(Some(crate::db::meetings::MeetingAutoEndCandidate {
            meeting_id,
            provider: MeetingProvider::Zoom,
            provider_meeting_id: provider_meeting_id.clone(),
        }))
    });
    db.expect_set_meeting_auto_end_check_outcome().never();
    db.expect_release_meeting_auto_end_check_claim()
        .times(1)
        .withf(move |mid| *mid == meeting_id)
        .returning(|_| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup meetings provider mock
    let mut mp = MockMeetingsProvider::new();
    mp.expect_end_meeting()
        .times(1)
        .returning(|_| Box::pin(async { Err(MeetingProviderError::Network("timeout".to_string())) }));
    let mp: DynMeetingsProvider = Arc::new(mp);

    // Setup worker and auto-end meeting
    let worker = sample_auto_end_worker(db, mp);
    let result = worker.auto_end_meeting().await;

    // Check result is a retryable provider error
    assert!(matches!(
        result,
        Err(SyncError::Provider(MeetingProviderError::Network(_)))
    ));
}

#[tokio::test]
async fn test_worker_claim_recovery_marks_stale_claims_unknown() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_mark_stale_meeting_auto_end_checks_unknown()
        .times(1)
        .withf(|timeout| *timeout == Duration::from_mins(15))
        .returning(|_| Ok(2));
    db.expect_mark_stale_meeting_syncs_unknown()
        .times(1)
        .withf(|timeout| *timeout == Duration::from_mins(15))
        .returning(|_| Ok(3));
    let db: DynDB = Arc::new(db);

    // Setup worker and recover stale claims
    let worker = sample_claim_recovery_worker(db);
    let count = worker.mark_stale_meeting_claims_unknown().await.unwrap();

    // Check result matches expectations
    assert_eq!(count, 5);
}

#[tokio::test]
async fn test_worker_claim_recovery_returns_auto_end_error() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_mark_stale_meeting_auto_end_checks_unknown()
        .times(1)
        .returning(|_| Err(anyhow!("auto-end claim recovery failed")));
    db.expect_mark_stale_meeting_syncs_unknown().never();
    let db: DynDB = Arc::new(db);

    // Setup worker and recover stale claims
    let worker = sample_claim_recovery_worker(db);
    let result = worker.mark_stale_meeting_claims_unknown().await;

    // Check result matches expectations
    assert!(result.is_err());
}

#[tokio::test]
async fn test_worker_claim_recovery_returns_sync_error() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_mark_stale_meeting_auto_end_checks_unknown()
        .times(1)
        .returning(|_| Ok(2));
    db.expect_mark_stale_meeting_syncs_unknown()
        .times(1)
        .returning(|_| Err(anyhow!("sync claim recovery failed")));
    let db: DynDB = Arc::new(db);

    // Setup worker and recover stale claims
    let worker = sample_claim_recovery_worker(db);
    let result = worker.mark_stale_meeting_claims_unknown().await;

    // Check result matches expectations
    assert!(result.is_err());
}

#[tokio::test]
async fn test_worker_sync_meeting_creates_new_meeting() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();
    let meeting_id = Uuid::new_v4();
    let starts_at = chrono::DateTime::from_timestamp(1_900_000_000, 0).unwrap();
    let meeting = Meeting {
        duration: Some(Duration::from_mins(30)),
        event_id: Some(event_id),
        meeting_id: Some(meeting_id),
        provider_meeting_id: None,
        starts_at: Some(starts_at),
        topic: Some("Test Meeting".to_string()),
        ..Default::default()
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_out_of_sync()
        .times(1)
        .returning(move || Ok(Some(meeting.clone())));
    db.expect_assign_zoom_host_user()
        .times(1)
        .withf(move |meeting, pool_users, max, start, end| {
            meeting.event_id == Some(event_id)
                && meeting.session_id.is_none()
                && meeting.sync_claimed_at.is_none()
                && pool_users == vec!["host@example.com".to_string()]
                && *max == 1
                && *start == starts_at
                && *end == starts_at + chrono::Duration::minutes(30)
        })
        .returning(|_, _, _, _, _| Ok(Some("host@example.com".to_string())));
    db.expect_add_meeting()
        .times(1)
        .withf(move |m| {
            m.meeting_id == Some(meeting_id)
                && m.provider_meeting_id == Some("zoom-123".to_string())
                && m.provider_host_user_id == Some("host@example.com".to_string())
                && m.join_url == Some("https://zoom.us/j/123".to_string())
        })
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
    let mut worker = sample_sync_worker(db, mp);
    let synced = worker.sync_meeting().await.unwrap();

    // Check result matches expectations
    assert!(synced);
}

#[tokio::test]
async fn test_worker_sync_meeting_updates_existing_meeting() {
    // Setup identifiers and data structures
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
    db.expect_claim_meeting_out_of_sync()
        .times(1)
        .returning(move || Ok(Some(meeting.clone())));
    db.expect_update_meeting()
        .times(1)
        .withf(move |m| {
            m.meeting_id == Some(meeting_id) && m.join_url == Some("https://zoom.us/j/456".to_string())
        })
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
    let mut worker = sample_sync_worker(db, mp);
    let synced = worker.sync_meeting().await.unwrap();

    // Check result matches expectations
    assert!(synced);
}

#[tokio::test]
async fn test_worker_sync_meeting_deletes_meeting() {
    // Setup identifiers and data structures
    let meeting_id = Uuid::new_v4();
    let provider_meeting_id = "zoom-789".to_string();
    let meeting = Meeting {
        delete: Some(true),
        meeting_id: Some(meeting_id),
        provider_meeting_id: Some(provider_meeting_id.clone()),
        ..Default::default()
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_out_of_sync()
        .times(1)
        .returning(move || Ok(Some(meeting.clone())));
    db.expect_delete_meeting()
        .times(1)
        .withf(move |m| m.meeting_id == Some(meeting_id))
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
    let mut worker = sample_sync_worker(db, mp);
    let synced = worker.sync_meeting().await.unwrap();

    // Check result matches expectations
    assert!(synced);
}

#[tokio::test]
async fn test_worker_sync_meeting_delete_not_found_succeeds() {
    // Setup identifiers and data structures
    let meeting_id = Uuid::new_v4();
    let provider_meeting_id = "zoom-notfound".to_string();
    let meeting = Meeting {
        delete: Some(true),
        meeting_id: Some(meeting_id),
        provider_meeting_id: Some(provider_meeting_id.clone()),
        ..Default::default()
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_out_of_sync()
        .times(1)
        .returning(move || Ok(Some(meeting.clone())));
    db.expect_delete_meeting()
        .times(1)
        .withf(move |m| m.meeting_id == Some(meeting_id))
        .returning(|_| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup meetings provider mock
    let mut mp = MockMeetingsProvider::new();
    mp.expect_delete_meeting()
        .times(1)
        .withf(move |pid| *pid == provider_meeting_id)
        .returning(|_| Box::pin(async { Err(MeetingProviderError::NotFound) }));
    let mp: DynMeetingsProvider = Arc::new(mp);

    // Setup worker and sync meeting
    let mut worker = sample_sync_worker(db, mp);
    let synced = worker.sync_meeting().await.unwrap();

    // Check result matches expectations
    assert!(synced);
}

#[tokio::test]
async fn test_worker_sync_meeting_no_pending_meeting() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_out_of_sync().times(1).returning(|| Ok(None));
    let db: DynDB = Arc::new(db);

    // Setup meetings provider mock
    let mut mp = MockMeetingsProvider::new();
    mp.expect_create_meeting().never();
    mp.expect_update_meeting().never();
    mp.expect_delete_meeting().never();
    let mp: DynMeetingsProvider = Arc::new(mp);

    // Setup worker and sync meeting
    let mut worker = sample_sync_worker(db, mp);
    let synced = worker.sync_meeting().await.unwrap();

    // Check result matches expectations
    assert!(!synced);
}

#[tokio::test]
async fn test_worker_sync_meeting_retryable_error_releases_claim() {
    // Setup identifiers and data structures
    let starts_at = chrono::DateTime::from_timestamp(1_900_010_000, 0).unwrap();
    let meeting = Meeting {
        duration: Some(Duration::from_mins(30)),
        meeting_id: Some(Uuid::new_v4()),
        provider_meeting_id: None,
        starts_at: Some(starts_at),
        ..Default::default()
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_out_of_sync()
        .times(1)
        .returning(move || Ok(Some(meeting.clone())));
    db.expect_assign_zoom_host_user()
        .times(1)
        .returning(|_, _, _, _, _| Ok(Some("host@example.com".to_string())));
    db.expect_release_meeting_sync_claim().times(1).returning(|_| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup meetings provider mock
    let mut mp = MockMeetingsProvider::new();
    mp.expect_create_meeting()
        .times(1)
        .returning(|_| Box::pin(async { Err(MeetingProviderError::Network("timeout".to_string())) }));
    let mp: DynMeetingsProvider = Arc::new(mp);

    // Setup worker and sync meeting
    let mut worker = sample_sync_worker(db, mp);
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
    let meeting_id = Uuid::new_v4();
    let starts_at = chrono::DateTime::from_timestamp(1_900_020_000, 0).unwrap();
    let meeting = Meeting {
        duration: Some(Duration::from_mins(30)),
        meeting_id: Some(meeting_id),
        provider_meeting_id: None,
        starts_at: Some(starts_at),
        ..Default::default()
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_out_of_sync()
        .times(1)
        .returning(move || Ok(Some(meeting.clone())));
    db.expect_assign_zoom_host_user()
        .times(1)
        .returning(|_, _, _, _, _| Ok(Some("host@example.com".to_string())));
    db.expect_set_meeting_error()
        .times(1)
        .withf(move |m, err| m.meeting_id == Some(meeting_id) && err.contains("invalid meeting data"))
        .returning(|_, _| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup meetings provider mock
    let mut mp = MockMeetingsProvider::new();
    mp.expect_create_meeting().times(1).returning(|_| {
        Box::pin(async { Err(MeetingProviderError::Client("invalid meeting data".to_string())) })
    });
    let mp: DynMeetingsProvider = Arc::new(mp);

    // Setup worker and sync meeting
    let mut worker = sample_sync_worker(db, mp);
    let synced = worker.sync_meeting().await.unwrap();

    // Check result matches expectations
    assert!(synced);
}

#[tokio::test]
async fn test_worker_sync_meeting_no_slots_available_records_error() {
    // Setup identifiers and data structures
    let meeting_id = Uuid::new_v4();
    let starts_at = chrono::DateTime::from_timestamp(1_900_030_000, 0).unwrap();
    let meeting = Meeting {
        duration: Some(Duration::from_mins(30)),
        meeting_id: Some(meeting_id),
        provider_meeting_id: None,
        starts_at: Some(starts_at),
        ..Default::default()
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_out_of_sync()
        .times(1)
        .returning(move || Ok(Some(meeting.clone())));
    db.expect_assign_zoom_host_user()
        .times(1)
        .returning(|_, _, _, _, _| Ok(None));
    db.expect_set_meeting_error()
        .times(1)
        .withf(move |m, err| m.meeting_id == Some(meeting_id) && err.contains("no meeting slots available"))
        .returning(|_, _| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup meetings provider mock
    let mut mp = MockMeetingsProvider::new();
    mp.expect_create_meeting().never();
    let mp: DynMeetingsProvider = Arc::new(mp);

    // Setup worker and sync meeting
    let mut worker = sample_sync_worker(db, mp);
    let synced = worker.sync_meeting().await.unwrap();

    // Check result matches expectations
    assert!(synced);
}

#[tokio::test]
async fn test_worker_sync_meeting_delete_without_provider_id() {
    // Setup identifiers and data structures
    let meeting_id = Uuid::new_v4();
    let meeting = Meeting {
        delete: Some(true),
        meeting_id: Some(meeting_id),
        provider_meeting_id: None,
        ..Default::default()
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_out_of_sync()
        .times(1)
        .returning(move || Ok(Some(meeting.clone())));
    db.expect_delete_meeting()
        .times(1)
        .withf(move |m| m.meeting_id == Some(meeting_id))
        .returning(|_| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup meetings provider mock
    let mut mp = MockMeetingsProvider::new();
    mp.expect_delete_meeting().never();
    let mp: DynMeetingsProvider = Arc::new(mp);

    // Setup worker and sync meeting
    let mut worker = sample_sync_worker(db, mp);
    let synced = worker.sync_meeting().await.unwrap();

    // Check result matches expectations
    assert!(synced);
}

#[tokio::test]
async fn test_worker_sync_meeting_provider_not_configured_records_error() {
    // Setup identifiers and data structures
    let meeting_id = Uuid::new_v4();
    let meeting = Meeting {
        meeting_id: Some(meeting_id),
        provider_meeting_id: None,
        ..Default::default()
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_meeting_out_of_sync()
        .times(1)
        .returning(move || Ok(Some(meeting.clone())));
    db.expect_set_meeting_error()
        .times(1)
        .withf(move |m, err| m.meeting_id == Some(meeting_id) && err.contains("provider not configured"))
        .returning(|_, _| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup worker with no providers configured
    let mut worker = sample_sync_worker_no_providers(db);
    let synced = worker.sync_meeting().await.unwrap();

    // Check result matches expectations
    assert!(synced);
}

// Helpers.

/// Create a sample auto-end worker with mock dependencies.
fn sample_auto_end_worker(db: DynDB, mp: DynMeetingsProvider) -> MeetingsAutoEndWorker {
    let mut providers = HashMap::new();
    providers.insert(MeetingProvider::Zoom, mp);
    MeetingsAutoEndWorker {
        cancellation_token: CancellationToken::new(),
        db,
        providers: Arc::new(providers),
    }
}

/// Create a sample auto-end worker with no providers configured.
fn sample_auto_end_worker_no_providers(db: DynDB) -> MeetingsAutoEndWorker {
    MeetingsAutoEndWorker {
        cancellation_token: CancellationToken::new(),
        db,
        providers: Arc::new(HashMap::new()),
    }
}

/// Create a sample claim recovery worker with mock dependencies.
fn sample_claim_recovery_worker(db: DynDB) -> MeetingsClaimRecoveryWorker {
    MeetingsClaimRecoveryWorker {
        cancellation_token: CancellationToken::new(),
        db,
    }
}

/// Create a sample sync worker with mock dependencies.
fn sample_sync_worker(db: DynDB, mp: DynMeetingsProvider) -> MeetingsSyncWorker {
    let mut providers = HashMap::new();
    providers.insert(MeetingProvider::Zoom, mp);
    MeetingsSyncWorker {
        cancellation_token: CancellationToken::new(),
        db,
        providers: Arc::new(providers),
        zoom_cfg: Some(sample_zoom_cfg()),
    }
}

/// Create a sample sync worker with no providers configured.
fn sample_sync_worker_no_providers(db: DynDB) -> MeetingsSyncWorker {
    MeetingsSyncWorker {
        cancellation_token: CancellationToken::new(),
        db,
        providers: Arc::new(HashMap::new()),
        zoom_cfg: Some(sample_zoom_cfg()),
    }
}

/// Create a sample Zoom configuration for testing.
fn sample_zoom_cfg() -> MeetingsZoomConfig {
    MeetingsZoomConfig {
        account_id: "account-id".to_string(),
        client_id: "client-id".to_string(),
        client_secret: "client-secret".to_string(),
        enabled: true,
        host_pool_users: vec!["host@example.com".to_string()],
        max_participants: 100,
        max_simultaneous_meetings_per_host: 1,
        webhook_secret_token: "webhook-secret".to_string(),
    }
}
