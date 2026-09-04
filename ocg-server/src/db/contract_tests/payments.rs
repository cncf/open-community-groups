//! Contract tests for the `DBPayments` functions.

use anyhow::{Context, Result, anyhow};
use tokio_postgres::error::SqlState;
use uuid::Uuid;

use crate::{
    db::{
        dashboard::group::DBDashboardGroup,
        payments::{
            DBPayments, EventPurchaseRefundKind, EventPurchaseRefundStatus,
            PrepareEventCheckoutPurchaseInput, PrepareEventCheckoutPurchaseResult,
            ReconcileEventPurchaseForCheckoutSessionInput, ReconcileEventPurchaseResult,
        },
    },
    types::payments::{EventPurchaseChargeModel, EventPurchaseStatus, PaymentProvider},
};

use super::helpers::{
    checkout_buyer_id, community_id, contract_tests_db, contract_tests_pool,
    document_adjustment_id, document_credit_note_id, document_purchase_id, document_refund_id,
    external_checkout_buyer_id, external_complete_purchase_id, external_complete_user_id,
    external_event_id, external_refund_purchase_id, external_refund_user_id,
    external_ticket_type_id, free_buyer_id, free_purchase_id, group_id, organizer_id,
    paid_event_id, paid_ticket_type_id, reconcile_buyer_id, reconcile_due_event_id,
    refund_approve_purchase_id, refund_begin_purchase_id, refund_event_id,
    refund_lifecycle_purchase_id, refund_recovery_purchase_id, refund_recovery_refund_id,
    refund_reject_buyer_id, refund_reject_purchase_id, subgroup_id, summary_purchase_id,
};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_and_finalize_event_refund_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Claim the provider-complete durable refund from contract fixtures
    let refund = db
        .claim_event_purchase_refund(PaymentProvider::Stripe)
        .await?
        .context("provider-complete contract refund should be claimable")?;

    // Check the claimed JSON contract and persisted provider outcome
    assert_eq!(refund.community_id, community_id());
    assert_eq!(refund.event_id, paid_event_id());
    assert_eq!(refund.event_purchase_id, refund_approve_purchase_id());
    assert_eq!(refund.status, EventPurchaseRefundStatus::Processing);
    assert!(refund.provider_refunded_at.is_some());

    // Finalize local state with the current worker claim
    db.finalize_event_purchase_refund(
        refund.event_purchase_refund_id,
        refund.claim_id.context("refund claim id should be present")?,
        serde_json::json!({"scenario": "contract"}),
        Some(PaymentProvider::Stripe),
    )
    .await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_event_purchase_application_fee_adjustment_deserializes() -> Result<()> {
    // Setup the contract database and claim the pending adjustment fixture
    let db = contract_tests_db()?;
    let adjustment = db
        .claim_event_purchase_application_fee_adjustment(PaymentProvider::Stripe)
        .await?
        .context("contract application-fee adjustment should be claimable")?;

    // Check the complete provider request context deserializes
    assert_eq!(adjustment.amount_minor, 25);
    assert_eq!(adjustment.connected_seller_id, "acct_contract_documents");
    assert_eq!(adjustment.currency_code, "USD");
    assert_eq!(
        adjustment.event_purchase_application_fee_adjustment_id,
        document_adjustment_id()
    );
    assert_eq!(adjustment.event_purchase_id, document_purchase_id());
    assert_eq!(
        adjustment.idempotency_key,
        "event-purchase-application-fee-adjustment-contract-documents"
    );
    assert_eq!(adjustment.kind, "purchase-refund");
    assert_eq!(
        adjustment.provider_application_fee_id,
        "fee_contract_documents"
    );

    // Complete the claim so it cannot interfere with later worker contracts
    db.record_event_purchase_application_fee_adjustment_succeeded(
        adjustment.event_purchase_application_fee_adjustment_id,
        adjustment.claim_id,
        "fr_contract_documents".to_string(),
    )
    .await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_event_purchase_credit_note_deserializes() -> Result<()> {
    // Setup the contract database and claim the pending credit-note fixture
    let db = contract_tests_db()?;
    let credit_note = db
        .claim_event_purchase_credit_note(PaymentProvider::Stripe)
        .await?
        .context("contract credit note should be claimable")?;

    // Check the complete provider request context deserializes
    assert_eq!(credit_note.amount_minor, 2500);
    assert_eq!(credit_note.connected_seller_id, "acct_contract_documents");
    assert_eq!(
        credit_note.event_purchase_credit_note_id,
        document_credit_note_id()
    );
    assert_eq!(credit_note.event_purchase_id, document_purchase_id());
    assert_eq!(credit_note.event_purchase_refund_id, document_refund_id());
    assert_eq!(
        credit_note.idempotency_key,
        "event-purchase-credit-note-contract-documents"
    );
    assert_eq!(credit_note.provider_invoice_id, "in_contract_documents");
    assert_eq!(credit_note.provider_refund_id, "re_contract_documents");
    assert_eq!(credit_note.tax_amount_minor, 0);

    // Issue the document so later attendee contracts cover the provider fields
    db.record_event_purchase_credit_note_succeeded(
        credit_note.event_purchase_credit_note_id,
        credit_note.claim_id,
        "cn_contract_documents".to_string(),
        Some("https://invoice.stripe.test/cn/contract-documents".to_string()),
        Some("https://invoice.stripe.test/cn/contract-documents.pdf".to_string()),
    )
    .await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_approve_external_event_refund_request_deserializes() -> Result<()> {
    // Setup the contract database and pending external refund fixture
    let db = contract_tests_db()?;

    // Approve the external refund request through the Rust contract
    let purchase = db
        .approve_external_event_refund_request(
            organizer_id(),
            group_id(),
            external_refund_purchase_id(),
            Some("Approved for contract coverage".to_string()),
            None,
        )
        .await?;

    // Check the completed refund ownership fields
    assert_eq!(purchase.community_id, community_id());
    assert_eq!(purchase.event_id, external_event_id());
    assert_eq!(purchase.transitioned, Some(true));
    assert_eq!(purchase.user_id, external_refund_user_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_complete_external_event_purchase_deserializes() -> Result<()> {
    // Setup the contract database and pending external purchase fixture
    let db = contract_tests_db()?;

    // Complete the external purchase through the Rust contract
    let purchase = db
        .complete_external_event_purchase(
            organizer_id(),
            group_id(),
            external_complete_purchase_id(),
            Some("Bank transfer matched".to_string()),
            None,
            None,
        )
        .await?;

    // Check the completed purchase ownership fields
    assert_eq!(purchase.community_id, community_id());
    assert_eq!(purchase.event_id, external_event_id());
    assert_eq!(purchase.transitioned, Some(true));
    assert_eq!(purchase.user_id, external_complete_user_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_purchase_notification_context_deserializes() -> Result<()> {
    // Setup the contract database and pending external purchase fixture
    let db = contract_tests_db()?;

    // Load the notification identifiers through the Rust contract
    let context = db
        .get_event_purchase_notification_context(group_id(), external_complete_purchase_id())
        .await?
        .expect("purchase notification context to exist");

    // Check the required identifier contract
    assert_eq!(context.community_id, community_id());
    assert_eq!(context.event_id, external_event_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_complete_free_event_purchase_deserializes() -> Result<()> {
    // Setup the contract database and free purchase fixture
    let db = contract_tests_db()?;

    // Load the provider-free purchase snapshot before completing it
    let summary = db.get_event_purchase_summary(free_purchase_id()).await?;
    assert_eq!(summary.currency_code, None);

    // Complete the free purchase through the Rust contract
    let purchase = db.complete_free_event_purchase(free_purchase_id()).await?;

    // Check the completed purchase ownership fields
    assert_eq!(purchase.community_id, community_id());
    assert_eq!(purchase.event_id, paid_event_id());
    assert_eq!(purchase.user_id, free_buyer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_event_purchase_refund_lifecycle_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Queue a durable manual refund from deterministic contract data
    db.queue_event_refund_request_approval(
        organizer_id(),
        group_id(),
        refund_lifecycle_purchase_id(),
        Some("Approved for lifecycle contract".to_string()),
    )
    .await?;
    let refund = db.get_event_purchase_refund(refund_lifecycle_purchase_id()).await?;

    // Check required fields and initial workflow metadata
    assert_eq!(refund.amount_minor, 2500);
    assert_eq!(refund.currency_code, "USD");
    assert_eq!(refund.event_purchase_id, refund_lifecycle_purchase_id());
    assert_ne!(refund.event_purchase_refund_id, Uuid::nil());
    assert_eq!(
        refund.idempotency_key,
        format!("event-purchase-refund-{}", refund_lifecycle_purchase_id())
    );
    assert_eq!(refund.kind, EventPurchaseRefundKind::RefundRequestApproval);
    assert_eq!(refund.payment_provider, PaymentProvider::Stripe);
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderPending);

    // Check optional provider outcome fields are absent initially
    assert!(refund.failure_message.is_none());
    assert!(refund.finalized_at.is_none());
    assert!(refund.provider_refund_id.is_none());
    assert!(refund.provider_refunded_at.is_none());

    // Record the in-progress provider refund
    let refund = db
        .record_event_purchase_refund_pending(
            refund.event_purchase_refund_id,
            refund.idempotency_key.clone(),
            "re_contract_refund_lifecycle".to_string(),
            refund.claim_id,
        )
        .await?;

    // Check the pending provider identifier and workflow state
    assert_eq!(refund.event_purchase_id, refund_lifecycle_purchase_id());
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderPending);

    assert!(refund.failure_message.is_none());
    assert!(refund.finalized_at.is_none());
    assert_eq!(
        refund.provider_refund_id.as_deref(),
        Some("re_contract_refund_lifecycle")
    );
    assert!(refund.provider_refunded_at.is_none());

    // Record provider success for the same durable refund
    let refund = db
        .record_event_purchase_refund_succeeded(
            refund.event_purchase_refund_id,
            refund.idempotency_key.clone(),
            "re_contract_refund_lifecycle".to_string(),
            refund.claim_id,
        )
        .await?;

    // Check the successful provider outcome deserializes completely
    assert_eq!(refund.event_purchase_id, refund_lifecycle_purchase_id());
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderSucceeded);

    assert!(refund.failure_message.is_none());
    assert!(refund.finalized_at.is_none());
    assert_eq!(
        refund.provider_refund_id.as_deref(),
        Some("re_contract_refund_lifecycle")
    );
    assert!(refund.provider_refunded_at.is_some());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_purchase_recovery_summary_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load the deterministic purchase awaiting provider refund recovery
    let summary = db.get_event_purchase_summary(refund_recovery_purchase_id()).await?;

    // Check the recovery status crosses the SQL-to-Rust contract
    assert_eq!(summary.event_purchase_id, refund_recovery_purchase_id());
    assert_eq!(summary.status, EventPurchaseStatus::RefundRecoveryPending);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_purchase_refund_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load the deterministic post-finalization recovery record
    let refund = db.get_event_purchase_refund(refund_recovery_purchase_id()).await?;

    // Check the required durable refund contract
    assert_eq!(refund.amount_minor, 2500);
    assert_eq!(refund.currency_code, "USD");
    assert_eq!(refund.event_purchase_id, refund_recovery_purchase_id());
    assert_eq!(refund.event_purchase_refund_id, refund_recovery_refund_id());
    assert_eq!(
        refund.idempotency_key,
        "event-purchase-refund-00000000-0000-0000-0000-00000000c0fd-recovery"
    );
    assert_eq!(
        refund.kind,
        EventPurchaseRefundKind::AutomaticUnfulfillableCheckout
    );
    assert_eq!(refund.payment_provider, PaymentProvider::Stripe);
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderFailed);

    // Check the optional recovery outcome fields
    assert_eq!(
        refund.failure_message.as_deref(),
        Some("provider refund failed: re_contract_refund_failed")
    );
    assert!(refund.finalized_at.is_some());
    assert!(refund.provider_refund_id.is_none());
    assert!(refund.provider_refunded_at.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_purchase_refund_recovery_context_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load group-scoped recovery context for the deterministic refund
    let context = db
        .get_event_purchase_refund_recovery_context(group_id(), refund_recovery_purchase_id())
        .await?;

    // Check the app receives authoritative notification composition context
    assert_eq!(context.community_id, community_id());
    assert_eq!(context.event_id, refund_event_id());
    assert_eq!(
        context.event_purchase_refund_id,
        refund_recovery_refund_id()
    );
    assert!(!context.notification_required);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_purchase_summary_deserializes() -> Result<()> {
    // Setup the contract database and purchase fixture
    let db = contract_tests_db()?;

    // Load the purchase summary through the Rust contract
    let summary = db.get_event_purchase_summary(summary_purchase_id()).await?;

    // Check pricing, hold, status, and ticket fields
    assert_eq!(summary.amount_minor, 2500);
    assert_eq!(summary.charge_model, EventPurchaseChargeModel::DirectCharge);
    assert_eq!(summary.currency_code.as_deref(), Some("USD"));
    assert_eq!(summary.discount_amount_minor, 0);
    assert_eq!(summary.event_purchase_id, summary_purchase_id());
    assert_eq!(summary.event_ticket_type_id, paid_ticket_type_id());
    assert!(summary.external_payment_instructions.is_none());
    assert!(summary.external_payment_url.is_none());
    assert!(summary.hold_expires_at.is_some());
    assert_eq!(summary.provisional_platform_fee_amount_minor, 250);
    assert_eq!(summary.status, EventPurchaseStatus::Pending);
    assert_eq!(summary.ticket_title, "Contract Paid Ticket");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_purchase_document_context_deserializes() -> Result<()> {
    // Setup the contract database and resolve the attendee-owned invoice
    let db = contract_tests_db()?;
    let context = db
        .get_user_purchase_document_context(free_buyer_id(), document_purchase_id(), None)
        .await?
        .context("contract invoice context should exist")?;

    // Check immutable provider scope and document ownership deserialize
    assert_eq!(context.connected_seller_id, "acct_contract_documents");
    assert_eq!(context.payment_provider, PaymentProvider::Stripe);
    assert_eq!(context.provider_document_id, "in_contract_documents");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_prepare_event_checkout_purchase_deserializes() -> Result<()> {
    // Setup the contract database and checkout input
    let db = contract_tests_db()?;
    let input = PrepareEventCheckoutPurchaseInput {
        event_id: paid_event_id(),
        event_ticket_type_id: paid_ticket_type_id(),
        platform_fee_bps: 250,
        user_id: checkout_buyer_id(),

        admission_offer_id: None,
        discount_code: None,
        payment_provider: Some(PaymentProvider::Stripe),
        registration_answers: None,
    };

    // Prepare the checkout purchase through the Rust contract
    let checkout = match db.prepare_event_checkout_purchase(community_id(), &input).await? {
        PrepareEventCheckoutPurchaseResult::Conflict(conflict) => {
            return Err(anyhow!("unexpected checkout conflict: {conflict:?}"));
        }
        PrepareEventCheckoutPurchaseResult::Prepared(checkout) => *checkout,
    };

    // Check event, purchase, and recipient fields
    assert_eq!(checkout.community_name, "contract-community");
    assert_eq!(checkout.event_id, paid_event_id());
    assert_eq!(checkout.event_slug, "contract-paid-event");
    assert_eq!(checkout.group_slug, "contract-group");
    assert_eq!(
        checkout.venue.as_ref().and_then(|venue| venue.state_code.as_deref()),
        Some("CA")
    );
    assert_eq!(
        checkout.venue.as_ref().and_then(|venue| venue.state_name.as_deref()),
        Some("California")
    );
    assert_eq!(checkout.purchase.amount_minor, 2500);
    assert_eq!(
        checkout.purchase.charge_model,
        EventPurchaseChargeModel::DirectCharge
    );
    assert_eq!(
        checkout.purchase.event_ticket_type_id,
        paid_ticket_type_id()
    );
    assert!(checkout.purchase.external_payment_instructions.is_none());
    assert!(checkout.purchase.external_payment_url.is_none());
    assert!(checkout.purchase.hold_expires_at.is_some());
    assert_eq!(checkout.purchase.provisional_platform_fee_amount_minor, 62);
    assert_eq!(checkout.purchase.status, EventPurchaseStatus::Pending);
    assert_eq!(checkout.purchase.ticket_title, "Contract Paid Ticket");
    assert_eq!(
        checkout.seller.as_ref().map(|seller| seller.provider),
        Some(PaymentProvider::Stripe)
    );
    assert_eq!(
        checkout
            .seller
            .as_ref()
            .map(|seller| seller.connected_account_id.as_str()),
        Some("acct_contract")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_prepare_event_checkout_purchase_external_deserializes() -> Result<()> {
    // Setup the contract database and external checkout input
    let db = contract_tests_db()?;
    let input = PrepareEventCheckoutPurchaseInput {
        event_id: external_event_id(),
        event_ticket_type_id: external_ticket_type_id(),
        platform_fee_bps: 0,
        user_id: external_checkout_buyer_id(),

        admission_offer_id: None,
        discount_code: None,
        payment_provider: None,
        registration_answers: None,
    };

    // Prepare the external checkout purchase through the Rust contract
    let checkout = match db.prepare_event_checkout_purchase(community_id(), &input).await? {
        PrepareEventCheckoutPurchaseResult::Conflict(conflict) => {
            return Err(anyhow!("unexpected checkout conflict: {conflict:?}"));
        }
        PrepareEventCheckoutPurchaseResult::Prepared(checkout) => *checkout,
    };

    // Check external purchase summary fields
    assert_eq!(checkout.event_id, external_event_id());
    assert_eq!(checkout.event_slug, "contract-external-event");
    assert_eq!(checkout.purchase.amount_minor, 5000);
    assert_eq!(
        checkout.purchase.charge_model,
        EventPurchaseChargeModel::External
    );
    assert_eq!(checkout.purchase.currency_code.as_deref(), Some("USD"));
    assert_eq!(
        checkout.purchase.event_ticket_type_id,
        external_ticket_type_id()
    );
    assert_eq!(
        checkout.purchase.external_payment_instructions.as_deref(),
        Some("Wire transfer using the purchase reference.")
    );
    assert_eq!(
        checkout.purchase.external_payment_url.as_deref(),
        Some("https://pay.example.test/contract-external")
    );
    assert!(checkout.purchase.hold_expires_at.is_some());
    assert_eq!(checkout.purchase.provisional_platform_fee_amount_minor, 0);
    assert_eq!(checkout.purchase.status, EventPurchaseStatus::Pending);
    assert_eq!(checkout.purchase.ticket_title, "External Admission");
    assert!(checkout.seller.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_queue_event_refund_request_approval_blocks_event_writers() -> Result<()> {
    // Setup independent refund approval and event-lock connections
    let pool = contract_tests_pool()?;
    let approval_client = pool.get().await?;
    let event_client = pool.get().await?;

    // Queue approval while retaining the refund workflow locks
    approval_client.batch_execute("begin").await?;
    approval_client
        .query_one(
            "select queue_event_refund_request_approval($1::uuid, $2::uuid, $3::uuid, null::text)",
            &[&organizer_id(), &group_id(), &refund_begin_purchase_id()],
        )
        .await?;

    // Probe whether a competing writer can lock the owning event
    event_client
        .batch_execute("begin; set local lock_timeout = '250ms'")
        .await?;
    let lock_result = event_client
        .query_one(
            "select event_id from event where event_id = $1::uuid for update",
            &[&refund_event_id()],
        )
        .await;

    // Roll back the approval and lock probe before checking the outcome
    event_client.batch_execute("rollback").await?;
    approval_client.batch_execute("rollback").await?;

    // Check approval holds the event lock before refund workflow rows
    let lock_err = lock_result.expect_err("event writer should wait for refund approval");
    assert_eq!(lock_err.code(), Some(&SqlState::LOCK_NOT_AVAILABLE));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_queue_event_refund_request_approval_deserializes() -> Result<()> {
    // Setup the contract database and refund request fixture
    let db = contract_tests_db()?;

    // Queue organizer approval using deterministic request fixtures
    db.queue_event_refund_request_approval(
        organizer_id(),
        group_id(),
        refund_begin_purchase_id(),
        Some("Approved by contract test".to_string()),
    )
    .await?;

    // Load the queued durable refund through the Rust database contract
    let refund = db.get_event_purchase_refund(refund_begin_purchase_id()).await?;

    // Check required durable refund fields deserialize as expected
    assert_eq!(refund.amount_minor, 2500);
    assert_eq!(refund.currency_code, "USD");
    assert_eq!(refund.event_purchase_id, refund_begin_purchase_id());
    assert_eq!(refund.kind, EventPurchaseRefundKind::RefundRequestApproval);
    assert_eq!(refund.payment_provider, PaymentProvider::Stripe);
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderPending);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_reconcile_event_purchase_for_checkout_session_deserializes() -> Result<()> {
    // Setup the contract database and provider checkout references
    let db = contract_tests_db()?;

    // Reconcile the provider checkout through the Rust contract
    let result = db
        .reconcile_event_purchase_for_checkout_session(
            &ReconcileEventPurchaseForCheckoutSessionInput {
                payment_provider: PaymentProvider::Stripe,
                provider_charge_id: "ch_contract_reconcile".to_string(),
                provider_object_account_id: "acct_contract".to_string(),
                provider_payment_reference: "pi_contract_reconcile".to_string(),
                provider_session_id: "cs_contract_reconcile".to_string(),
                provider_total_minor: 2_500,
                tax_amount_minor: 0,

                provider_application_fee_id: None,
            },
        )
        .await?;

    // Require the completed reconciliation outcome
    let ReconcileEventPurchaseResult::Completed(purchase) = result else {
        panic!("reconciliation should complete the purchase");
    };

    // Check completed purchase ownership fields
    assert_eq!(purchase.community_id, community_id());
    assert_eq!(purchase.event_id, paid_event_id());
    assert_eq!(purchase.user_id, reconcile_buyer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_reconcile_next_event_enrollment_deserializes() -> Result<()> {
    // Setup the contract database and dedicated due event fixture
    let db = contract_tests_db()?;

    // Claim and reconcile the due event through the Rust JSON contract
    let outcome = db
        .reconcile_next_event_enrollment(None)
        .await?
        .context("due contract event should be claimable")?;

    // Check the reconciliation context deserializes completely
    assert_eq!(outcome.community_id, community_id());
    assert_eq!(outcome.event_id, reconcile_due_event_id());
    assert_eq!(outcome.group_id, subgroup_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_reject_event_refund_request_blocks_event_writers() -> Result<()> {
    // Setup independent refund rejection and event-lock connections
    let pool = contract_tests_pool()?;
    let event_client = pool.get().await?;
    let rejection_client = pool.get().await?;

    // Reject the request while retaining the refund workflow locks
    rejection_client.batch_execute("begin").await?;
    rejection_client
        .query_one(
            "select reject_event_refund_request($1::uuid, $2::uuid, $3::uuid, $4::text)",
            &[
                &organizer_id(),
                &group_id(),
                &refund_reject_purchase_id(),
                &"Rejected by lock contract",
            ],
        )
        .await?;

    // Probe whether a competing writer can lock the owning event
    event_client
        .batch_execute("begin; set local lock_timeout = '250ms'")
        .await?;
    let lock_result = event_client
        .query_one(
            "select event_id from event where event_id = $1::uuid for update",
            &[&refund_event_id()],
        )
        .await;

    // Roll back the rejection and lock probe before checking the outcome
    event_client.batch_execute("rollback").await?;
    rejection_client.batch_execute("rollback").await?;

    // Check rejection holds the event lock before refund workflow rows
    let lock_err = lock_result.expect_err("event writer should wait for refund rejection");
    assert_eq!(lock_err.code(), Some(&SqlState::LOCK_NOT_AVAILABLE));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_reject_event_refund_request_deserializes() -> Result<()> {
    // Setup the contract database and pending refund request
    let db = contract_tests_db()?;

    // Reject the refund request through the Rust contract
    let purchase = db
        .reject_event_refund_request(
            organizer_id(),
            group_id(),
            refund_reject_purchase_id(),
            "Rejected by contract test".to_string(),
        )
        .await?;

    // Check the returned purchase ownership fields
    assert_eq!(purchase.community_id, community_id());
    assert_eq!(purchase.event_id, paid_event_id());
    assert_eq!(purchase.user_id, refund_reject_buyer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_sync_external_payments_config_deserializes() -> Result<()> {
    // Setup the contract database and operator allowlist payload
    let db = contract_tests_db()?;
    let config = crate::config::ExternalPaymentsConfig {
        allowed_countries: vec!["US".to_string()],
        default_payment_window_hours: 72,
        max_payment_window_hours: 336,
    };

    // Sync the singleton configuration through the Rust contract
    db.sync_external_payments_config(Some(config)).await?;

    // Check the group settings context still deserializes after the sync
    let context = db
        .get_group_external_payments_context(community_id(), group_id())
        .await?;
    assert!(context.configured);
    assert!(context.eligible);
    assert!(context.enabled);
    assert_eq!(context.default_payment_window_hours, Some(72));
    assert_eq!(context.max_payment_window_hours, Some(336));

    Ok(())
}
