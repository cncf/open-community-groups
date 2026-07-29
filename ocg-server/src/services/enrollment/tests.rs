use std::sync::Arc;

use tokio_util::sync::CancellationToken;

use crate::{
    db::{DynDB, mock::MockDB},
    types::payments::PaymentProvider,
};

use super::EnrollmentWorker;

#[tokio::test]
async fn test_run_stops_before_database_work_when_canceled() {
    // Setup a canceled worker that must not reconcile enrollment
    let mut db = MockDB::new();
    db.expect_reconcile_next_event_enrollment().never();
    let db: DynDB = Arc::new(db);
    let worker = EnrollmentWorker {
        cancellation_token: CancellationToken::new(),
        db,
        payment_provider: Some(PaymentProvider::Stripe),
    };
    worker.cancellation_token.cancel();

    // Run the worker through graceful shutdown
    worker.run().await;
}
