//! Background worker health type definitions.

use serde::{Deserialize, Serialize};

/// Backlog signals for one durable job queue.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct QueueHealth {
    /// Jobs waiting to be claimed.
    pub pending: i64,
    /// Jobs currently claimed by a worker.
    pub processing: i64,

    /// Age in seconds of the oldest job still waiting, when any is pending.
    pub oldest_pending_age_secs: Option<i64>,
}

/// Backlog signals for every durable job queue.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct WorkerQueueHealth {
    /// Durable badge award job queue.
    pub badge_award_jobs: QueueHealth,
    /// Notification delivery queue.
    pub notifications: QueueHealth,
    /// Durable payment job queue.
    pub payment_jobs: QueueHealth,
}
