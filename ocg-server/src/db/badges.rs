//! Database operations for durable badge award processing.

use std::time::Duration;

use anyhow::{Result, anyhow};
use async_trait::async_trait;
use serde::Deserialize;
use tracing::instrument;
use uuid::Uuid;

use crate::db::PgExecutor;

/// Database operations used by badge award workers.
#[async_trait]
pub(crate) trait DBBadges {
    /// Claims the oldest badge award job ready for processing.
    async fn claim_badge_award_job(&self) -> Result<Option<ClaimedBadgeAwardJob>>;

    /// Deletes completed badge award summaries outside their retention window.
    async fn cleanup_badge_award_jobs(&self, retention: Duration) -> Result<usize>;

    /// Processes one bounded batch from an owned badge award claim.
    async fn process_badge_award_job_batch(
        &self,
        badge_award_job_id: Uuid,
        claim_id: Uuid,
        batch_size: usize,
        rate_limit: usize,
    ) -> Result<BadgeAwardBatchOutcome>;

    /// Records a processing failure and releases or terminally fails the claim.
    async fn record_badge_award_job_failure(
        &self,
        badge_award_job_id: Uuid,
        claim_id: Uuid,
        error: String,
        max_failures: usize,
    ) -> Result<bool>;

    /// Requeues badge award claims abandoned by interrupted workers.
    async fn recover_stale_badge_award_jobs(
        &self,
        max_failures: usize,
        processing_timeout: Duration,
    ) -> Result<usize>;
}

#[async_trait]
impl<T> DBBadges for T
where
    T: PgExecutor + Send + Sync,
{
    /// [`DBBadges::claim_badge_award_job`].
    #[instrument(skip(self), err)]
    async fn claim_badge_award_job(&self) -> Result<Option<ClaimedBadgeAwardJob>> {
        self.fetch_json_opt("select claim_badge_award_job()", &[]).await
    }

    /// [`DBBadges::cleanup_badge_award_jobs`].
    #[instrument(skip(self), err)]
    async fn cleanup_badge_award_jobs(&self, retention: Duration) -> Result<usize> {
        let retention = duration_seconds_i64(retention, "badge award retention is too large")?;
        let count: i32 = self
            .fetch_scalar_one(
                "select cleanup_badge_award_jobs($1::bigint)::integer",
                &[&retention],
            )
            .await?;

        usize::try_from(count).map_err(|_| anyhow!("invalid badge award cleanup count"))
    }

    /// [`DBBadges::process_badge_award_job_batch`].
    #[instrument(skip(self), err)]
    async fn process_badge_award_job_batch(
        &self,
        badge_award_job_id: Uuid,
        claim_id: Uuid,
        batch_size: usize,
        rate_limit: usize,
    ) -> Result<BadgeAwardBatchOutcome> {
        let batch_size = i32::try_from(batch_size)?;
        let rate_limit = i32::try_from(rate_limit)?;
        self.fetch_json_one(
            "select process_badge_award_job_batch($1::uuid, $2::uuid, $3::integer, $4::integer)",
            &[&badge_award_job_id, &claim_id, &batch_size, &rate_limit],
        )
        .await
    }

    /// [`DBBadges::record_badge_award_job_failure`].
    #[instrument(skip(self, error), err)]
    async fn record_badge_award_job_failure(
        &self,
        badge_award_job_id: Uuid,
        claim_id: Uuid,
        error: String,
        max_failures: usize,
    ) -> Result<bool> {
        let max_failures = i32::try_from(max_failures)?;
        self.fetch_scalar_one(
            "select record_badge_award_job_failure($1::uuid, $2::uuid, $3::text, $4::integer)::boolean",
            &[&badge_award_job_id, &claim_id, &error, &max_failures],
        )
        .await
    }

    /// [`DBBadges::recover_stale_badge_award_jobs`].
    #[instrument(skip(self), err)]
    async fn recover_stale_badge_award_jobs(
        &self,
        max_failures: usize,
        processing_timeout: Duration,
    ) -> Result<usize> {
        let max_failures = i32::try_from(max_failures)?;
        let processing_timeout = duration_seconds_i64(
            processing_timeout,
            "badge award processing timeout is too large",
        )?;
        let count: i32 = self
            .fetch_scalar_one(
                "select recover_stale_badge_award_jobs($1::bigint, $2::integer)::integer",
                &[&processing_timeout, &max_failures],
            )
            .await?;

        usize::try_from(count).map_err(|_| anyhow!("invalid badge award recovery count"))
    }
}

/// Result of processing one bounded badge award batch.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
pub(crate) struct BadgeAwardBatchOutcome {
    /// Whether the durable job reached successful completion.
    pub completed: bool,
    /// Number of queued recipients consumed by this batch.
    pub processed_count: usize,
    /// Whether processing paused because the global issuance budget was exhausted.
    pub rate_limited: bool,
}

/// Ownership token for one durable badge award processing attempt.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
pub(crate) struct ClaimedBadgeAwardJob {
    /// Durable job identifier.
    pub badge_award_job_id: Uuid,
    /// Claim identifier required by every processing transition.
    pub claim_id: Uuid,
}

/// Converts a duration to the database integer type.
fn duration_seconds_i64(duration: Duration, overflow_message: &str) -> Result<i64> {
    i64::try_from(duration.as_secs()).map_err(|_| anyhow!("{overflow_message}"))
}
