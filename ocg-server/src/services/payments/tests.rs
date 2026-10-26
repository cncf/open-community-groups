//! Shared helpers for payments service tests.

use serde_json::{Value, json};
use uuid::Uuid;

use crate::types::payments::PaymentProvider;

use super::MockPaymentsProvider;

/// Reports whether refund approval template data names the event and payment origin.
pub(super) fn approval_template_matches(
    template_data: &Value,
    event_id: Uuid,
    external_payment: bool,
) -> bool {
    template_data["event"]["event_id"] == json!(event_id)
        && template_data["external_payment"] == json!(external_payment)
}

/// Returns a Stripe provider mock that answers only its provider identity.
pub(super) fn stripe_provider() -> MockPaymentsProvider {
    let mut provider = MockPaymentsProvider::new();
    provider.expect_provider().return_const(PaymentProvider::Stripe);
    provider
}
