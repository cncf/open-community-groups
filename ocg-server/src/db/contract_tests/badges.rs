//! Contract tests for the `DBBadges` functions.

use anyhow::{Context, Result};

use crate::db::badges::DBBadges;

use super::helpers::{badge_award_job_id, contract_tests_db};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_badge_award_worker_deserializes() -> Result<()> {
    // Setup the contract database wrapper
    let db = contract_tests_db()?;

    // Claim and process the seeded pending award job
    let claim = db
        .claim_badge_award_job()
        .await?
        .context("contract badge award job should be claimable")?;
    let outcome = db
        .process_badge_award_job_batch(claim.badge_award_job_id, claim.claim_id, 25, 500)
        .await?;

    // Check worker claim and batch outcome JSON deserialize into Rust DTOs
    assert_eq!(claim.badge_award_job_id, badge_award_job_id());
    assert!(outcome.completed);
    assert_eq!(outcome.processed_count, 1);
    assert!(!outcome.rate_limited);

    Ok(())
}
