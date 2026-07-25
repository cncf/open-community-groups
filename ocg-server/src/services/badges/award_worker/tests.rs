use std::sync::Arc;

use anyhow::anyhow;
use mockall::predicate::eq;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::db::{
    badges::{BadgeAwardBatchOutcome, ClaimedBadgeAwardJob},
    mock::MockDB,
};

use super::{
    AWARD_BATCH_SIZE, AWARD_RATE_LIMIT_PER_MINUTE, BadgeAwardRecoveryWorker, BadgeAwardWorker,
    COMPLETED_JOB_RETENTION, MAX_FAILURES, PROCESSING_TIMEOUT,
};

#[tokio::test]
async fn process_next_award_job_leaves_queue_idle_when_no_work_is_due() {
    // Setup an empty durable queue and forbid processing calls
    let mut db = MockDB::new();
    db.expect_claim_badge_award_job().times(1).return_once(|| Ok(None));
    db.expect_process_badge_award_job_batch().never();
    let worker = badge_award_worker(db);

    // Attempt one worker iteration
    let processed = worker
        .process_next_award_job()
        .await
        .expect("empty queue lookup to succeed");

    // Check the worker reports idle without mutating durable work
    assert!(!processed);
}

#[tokio::test]
async fn process_next_award_job_processes_one_bounded_batch() {
    // Setup one claim and require the fixed batch and global-rate controls
    let job = claimed_job();
    let badge_award_job_id = job.badge_award_job_id;
    let claim_id = job.claim_id;
    let mut db = MockDB::new();
    db.expect_claim_badge_award_job()
        .times(1)
        .return_once(move || Ok(Some(job)));
    db.expect_process_badge_award_job_batch()
        .with(
            eq(badge_award_job_id),
            eq(claim_id),
            eq(AWARD_BATCH_SIZE),
            eq(AWARD_RATE_LIMIT_PER_MINUTE),
        )
        .times(1)
        .return_once(|_, _, _, _| {
            Ok(BadgeAwardBatchOutcome {
                completed: false,
                processed_count: AWARD_BATCH_SIZE,
                rate_limited: false,
            })
        });
    db.expect_record_badge_award_job_failure().never();
    let worker = badge_award_worker(db);

    // Process the claimed batch
    let processed = worker.process_next_award_job().await.expect("award batch to succeed");

    // Check successful partial progress keeps the worker active
    assert!(processed);
}

#[tokio::test]
async fn process_next_award_job_backs_off_when_global_rate_is_exhausted() {
    // Setup one claim whose database batch reaches the global rate boundary
    let job = claimed_job();
    let mut db = MockDB::new();
    db.expect_claim_badge_award_job()
        .times(1)
        .return_once(move || Ok(Some(job)));
    db.expect_process_badge_award_job_batch()
        .times(1)
        .return_once(|_, _, _, _| {
            Ok(BadgeAwardBatchOutcome {
                completed: false,
                processed_count: 0,
                rate_limited: true,
            })
        });
    db.expect_record_badge_award_job_failure().never();
    let worker = badge_award_worker(db);

    // Process the rate-limited claim release
    let processed = worker
        .process_next_award_job()
        .await
        .expect("rate-limited batch to release its claim");

    // Check the worker selects the idle backoff instead of claiming more work
    assert!(!processed);
}

#[tokio::test]
async fn process_next_award_job_releases_failed_claim_for_retry() {
    // Setup one claimed batch that fails and must be released durably
    let job = claimed_job();
    let badge_award_job_id = job.badge_award_job_id;
    let claim_id = job.claim_id;
    let mut db = MockDB::new();
    db.expect_claim_badge_award_job()
        .times(1)
        .return_once(move || Ok(Some(job)));
    db.expect_process_badge_award_job_batch()
        .times(1)
        .return_once(|_, _, _, _| Err(anyhow!("temporary database failure")));
    db.expect_record_badge_award_job_failure()
        .withf(move |job_id, expected_claim_id, error, max_failures| {
            *job_id == badge_award_job_id
                && *expected_claim_id == claim_id
                && error == "temporary database failure"
                && *max_failures == MAX_FAILURES
        })
        .times(1)
        .return_once(|_, _, _, _| Ok(false));
    let worker = badge_award_worker(db);

    // Process the failed batch
    let error = worker
        .process_next_award_job()
        .await
        .expect_err("processing failure to remain visible");

    // Check the original error remains visible after best-effort claim release
    assert_eq!(error.to_string(), "temporary database failure");
}

#[tokio::test]
async fn award_worker_does_not_claim_after_cancellation() {
    // Setup an already canceled worker and forbid new claims
    let mut db = MockDB::new();
    db.expect_claim_badge_award_job().never();
    let cancellation_token = CancellationToken::new();
    cancellation_token.cancel();
    let worker = BadgeAwardWorker {
        cancellation_token,
        db: Arc::new(db),
    };

    // Run to completion and rely on the strict mock to check no mutation occurs
    worker.run().await;
}

#[tokio::test]
async fn recovery_worker_maintains_stale_claims_and_completed_summaries() {
    // Setup one recovery and cleanup maintenance pass
    let mut db = MockDB::new();
    db.expect_recover_stale_badge_award_jobs()
        .with(eq(MAX_FAILURES), eq(PROCESSING_TIMEOUT))
        .times(1)
        .return_once(|_, _| Ok(2));
    db.expect_cleanup_badge_award_jobs()
        .with(eq(COMPLETED_JOB_RETENTION))
        .times(1)
        .return_once(|_| Ok(3));
    let worker = BadgeAwardRecoveryWorker {
        cancellation_token: CancellationToken::new(),
        db: Arc::new(db),
    };

    // Run maintenance and rely on strict arguments to check both bounded operations
    worker.maintain().await;
}

/// Builds one worker around a strict database mock.
fn badge_award_worker(db: MockDB) -> BadgeAwardWorker {
    BadgeAwardWorker {
        cancellation_token: CancellationToken::new(),
        db: Arc::new(db),
    }
}

/// Builds one durable claim fixture.
fn claimed_job() -> ClaimedBadgeAwardJob {
    ClaimedBadgeAwardJob {
        badge_award_job_id: Uuid::new_v4(),
        claim_id: Uuid::new_v4(),
    }
}
