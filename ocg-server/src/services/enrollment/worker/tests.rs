use std::sync::Arc;

use tokio_util::sync::CancellationToken;

use crate::{db::mock::MockDB, types::payments::PaymentProvider};

use super::EnrollmentWorker;

#[tokio::test]
async fn test_run_forwards_payment_provider() {
    // Setup one reconciliation that requests shutdown after observing the provider
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_mock = cancellation_token.clone();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_reconcile_next_event_enrollment()
        .times(1)
        .withf(|provider| *provider == Some(PaymentProvider::Stripe))
        .returning(move |_| {
            cancellation_token_for_mock.cancel();
            Ok(None)
        });
    let worker = EnrollmentWorker {
        cancellation_token,
        db: Arc::new(db),
        payment_provider: Some(PaymentProvider::Stripe),
    };

    // Run the configured reconciliation once; the strict provider expectation
    // is the assertion, and only the mock can stop the worker
    worker.run().await;
}
