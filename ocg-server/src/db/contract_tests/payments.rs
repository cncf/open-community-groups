//! Contract tests for the `DBPayments` functions.

use anyhow::{Context, Result, anyhow};
use tokio_postgres::error::SqlState;
use uuid::Uuid;

use crate::{
    db::{
        dashboard::group::DBDashboardGroup,
        payments::{
            ClaimedPaymentJobWork, CompletePaymentJobRecoveryInput, DBPayments,
            EventPurchaseRefundKind, EventPurchaseRefundStatus, PrepareEventCheckoutPurchaseInput,
            PrepareEventCheckoutPurchaseResult, ReconcileEventPurchaseForCheckoutSessionInput,
            ReconcileEventPurchaseResult,
        },
    },
    types::payments::{
        EventPurchaseChargeModel, EventPurchaseStatus, PaymentJobKind, PaymentProvider,
    },
};

use super::helpers::{
    checkout_buyer_id, community_id, contract_tests_db, contract_tests_pool,
    document_adjustment_id, document_adjustment_job_id, document_credit_note_id,
    document_credit_note_job_id, document_purchase_id, document_refund_id, document_refund_job_id,
    external_checkout_buyer_id, external_complete_purchase_id, external_complete_user_id,
    external_event_id, external_refund_purchase_id, external_refund_user_id,
    external_ticket_type_id, free_buyer_id, free_purchase_id, group_id, organizer_id,
    paid_event_id, paid_ticket_type_id, reconcile_buyer_id, reconcile_due_event_id,
    refund_approve_job_id, refund_approve_purchase_id, refund_begin_purchase_id, refund_event_id,
    refund_lifecycle_purchase_id, refund_recovery_job_id, refund_recovery_purchase_id,
    refund_recovery_refund_id, refund_reject_buyer_id, refund_reject_purchase_id, subgroup_id,
    summary_purchase_id,
};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_and_finalize_event_refund_deserializes() -> Result<()> {
    // Setup the contract database and make the target refund claim deterministic
    let db = contract_tests_db()?;
    contract_tests_pool()?
        .get()
        .await?
        .execute(
            "
            update payment_job
            set next_attempt_at = case
                when payment_job_id = $1::uuid then current_timestamp - interval '1 minute'
                else current_timestamp + interval '1 minute'
            end
            where kind = 'event-purchase-refund'
            ",
            &[&refund_approve_job_id()],
        )
        .await?;

    // Claim the provider-complete durable refund from contract fixtures
    let job = db
        .claim_payment_job(PaymentJobKind::EventPurchaseRefund, PaymentProvider::Stripe)
        .await?
        .context("provider-complete contract refund should be claimable")?;
    let ClaimedPaymentJobWork::EventPurchaseRefund { refund } = job.work else {
        return Err(anyhow!("expected refund payment job"));
    };

    // Check the claimed JSON contract and persisted provider outcome
    assert_eq!(job.attempt_count, 1);
    assert_eq!(job.event_purchase_id, refund_approve_purchase_id());
    assert_eq!(
        job.idempotency_key,
        "event-purchase-refund-00000000-0000-0000-0000-00000000c0f6"
    );
    assert_eq!(job.payment_job_id, refund_approve_job_id());
    assert_eq!(job.payment_provider, PaymentProvider::Stripe);
    assert_eq!(refund.community_id, community_id());
    assert_eq!(refund.event_id, paid_event_id());
    assert_eq!(refund.event_purchase_id, refund_approve_purchase_id());
    assert_eq!(refund.payment_job_id, refund_approve_job_id());
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderSucceeded);
    assert!(refund.provider_refunded_at.is_some());

    // Finalize local state with the current worker claim
    db.finalize_event_purchase_refund(
        refund.event_purchase_refund_id,
        job.claim_id,
        serde_json::json!({"scenario": "contract"}),
        Some(PaymentProvider::Stripe),
    )
    .await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_payment_job_application_fee_adjustment_deserializes() -> Result<()> {
    // Setup the contract database and claim the pending adjustment fixture
    let db = contract_tests_db()?;
    let job = db
        .claim_payment_job(
            PaymentJobKind::EventPurchaseApplicationFeeAdjustment,
            PaymentProvider::Stripe,
        )
        .await?
        .context("contract application-fee adjustment should be claimable")?;
    let ClaimedPaymentJobWork::EventPurchaseApplicationFeeAdjustment {
        application_fee_adjustment: adjustment,
    } = job.work
    else {
        return Err(anyhow!("expected application-fee adjustment payment job"));
    };

    // Check the complete provider request context deserializes
    assert_eq!(job.attempt_count, 1);
    assert_eq!(job.event_purchase_id, document_purchase_id());
    assert_eq!(
        job.idempotency_key,
        "event-purchase-application-fee-adjustment-contract-documents"
    );
    assert_eq!(job.payment_job_id, document_adjustment_job_id());
    assert_eq!(job.payment_provider, PaymentProvider::Stripe);
    assert_eq!(adjustment.amount_minor, 25);
    assert_eq!(adjustment.connected_seller_id, "acct_contract_documents");
    assert_eq!(adjustment.currency_code, "USD");
    assert_eq!(
        adjustment.event_purchase_application_fee_adjustment_id,
        document_adjustment_id()
    );
    assert_eq!(adjustment.kind, "purchase-refund");
    assert_eq!(
        adjustment.provider_application_fee_id,
        "fee_contract_documents"
    );

    // Complete the claim so it cannot interfere with later worker contracts
    db.record_event_purchase_application_fee_adjustment_succeeded(
        adjustment.event_purchase_application_fee_adjustment_id,
        job.claim_id,
        "fr_contract_documents".to_string(),
    )
    .await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_payment_job_credit_note_deserializes() -> Result<()> {
    // Setup the contract database and claim the pending credit-note fixture
    let db = contract_tests_db()?;
    let job = db
        .claim_payment_job(
            PaymentJobKind::EventPurchaseCreditNote,
            PaymentProvider::Stripe,
        )
        .await?
        .context("contract credit note should be claimable")?;
    let ClaimedPaymentJobWork::EventPurchaseCreditNote { credit_note } = job.work else {
        return Err(anyhow!("expected credit-note payment job"));
    };

    // Check the complete provider request context deserializes
    assert_eq!(job.attempt_count, 1);
    assert_eq!(job.event_purchase_id, document_purchase_id());
    assert_eq!(
        job.idempotency_key,
        "event-purchase-credit-note-contract-documents"
    );
    assert_eq!(job.payment_job_id, document_credit_note_job_id());
    assert_eq!(job.payment_provider, PaymentProvider::Stripe);
    assert_eq!(credit_note.amount_minor, 2500);
    assert_eq!(credit_note.connected_seller_id, "acct_contract_documents");
    assert_eq!(
        credit_note.event_purchase_credit_note_id,
        document_credit_note_id()
    );
    assert_eq!(credit_note.event_purchase_refund_id, document_refund_id());
    assert_eq!(credit_note.provider_invoice_id, "in_contract_documents");
    assert_eq!(credit_note.provider_refund_id, "re_contract_documents");
    assert_eq!(credit_note.tax_amount_minor, 0);

    // Issue the document so later attendee contracts cover the provider fields
    db.record_event_purchase_credit_note_succeeded(
        credit_note.event_purchase_credit_note_id,
        job.claim_id,
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
async fn db_contracts_complete_payment_job_recovery_records_evidence() -> Result<()> {
    // Setup the contract database and a dedicated exhausted recovery job
    let db = contract_tests_db()?;
    let pool = contract_tests_pool()?;
    let adjustment_id = Uuid::parse_str("00000000-0000-0000-0000-00000000c13c")?;
    let payment_job_id = Uuid::parse_str("00000000-0000-0000-0000-00000000c13b")?;
    let client = pool.get().await?;
    client
        .execute(
            "
            insert into payment_job (
                attempt_count,
                event_purchase_id,
                failure_message,
                idempotency_key,
                kind,
                payment_job_id,
                payment_provider_id,
                status
            ) values (
                10,
                $1::uuid,
                'contract recovery failure',
                'contract-complete-payment-job-recovery',
                'event-purchase-application-fee-adjustment',
                $2::uuid,
                'stripe',
                'failed'
            )
            ",
            &[&document_purchase_id(), &payment_job_id],
        )
        .await?;
    client
        .execute(
            "
            insert into event_purchase_application_fee_adjustment (
                amount_minor,
                event_purchase_application_fee_adjustment_id,
                event_purchase_id,
                kind,
                payment_job_id
            ) values (
                25,
                $3::uuid,
                $1::uuid,
                'tax-reconciliation',
                $2::uuid
            )
            ",
            &[&document_purchase_id(), &payment_job_id, &adjustment_id],
        )
        .await?;

    // Complete the exhausted job with external provider evidence
    db.complete_payment_job_recovery(&CompletePaymentJobRecoveryInput {
        actor_user_id: organizer_id(),
        group_id: group_id(),
        payment_job_id,
        provider_object_id: "fr_contract_recovery".to_string(),
        recovery_note: "Recovered through Stripe dashboard".to_string(),
        recovery_reference: "ticket-contract-recovery".to_string(),
    })
    .await?;

    // Check the recovery evidence and provider outcome were persisted
    let client = pool.get().await?;
    let row = client
        .query_one(
            "
            select
                pj.recovery_note,
                pj.recovery_reference,
                pj.status,
                epafa.provider_application_fee_refund_id
            from payment_job pj
            join event_purchase_application_fee_adjustment epafa
                on epafa.payment_job_id = pj.payment_job_id
            where pj.payment_job_id = $1::uuid
            ",
            &[&payment_job_id],
        )
        .await?;
    assert_eq!(
        row.get::<_, &str>("recovery_note"),
        "Recovered through Stripe dashboard"
    );
    assert_eq!(
        row.get::<_, &str>("recovery_reference"),
        "ticket-contract-recovery"
    );
    assert_eq!(row.get::<_, &str>("status"), "completed");
    assert_eq!(
        row.get::<_, &str>("provider_application_fee_refund_id"),
        "fr_contract_recovery"
    );

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
    assert_eq!(refund.payment_job_id, refund_recovery_job_id());
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
    assert_ne!(refund.payment_job_id, Uuid::nil());
    assert_eq!(refund.payment_provider, PaymentProvider::Stripe);
    assert_eq!(refund.status, EventPurchaseRefundStatus::ProviderPending);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_record_payment_job_failure_releases_claim() -> Result<()> {
    // Setup a processing payment job with a deterministic claim
    let db = contract_tests_db()?;
    let pool = contract_tests_pool()?;
    let claim_id = Uuid::new_v4();
    pool.get()
        .await?
        .execute(
            "
            update payment_job
            set
                attempt_count = 1,
                claim_id = $2::uuid,
                claimed_at = current_timestamp,
                status = 'processing'
            where payment_job_id = $1::uuid
            ",
            &[&document_refund_job_id(), &claim_id],
        )
        .await?;

    // Release the claim through the Rust database wrapper
    db.record_payment_job_failure(
        document_refund_job_id(),
        claim_id,
        "contract retryable failure".to_string(),
    )
    .await?;

    // Check the job is failed and unclaimed for a later retry
    let row = pool
        .get()
        .await?
        .query_one(
            "
            select claim_id, failure_message, status
            from payment_job
            where payment_job_id = $1::uuid
            ",
            &[&document_refund_job_id()],
        )
        .await?;
    assert_eq!(row.get::<_, Option<Uuid>>("claim_id"), None);
    assert_eq!(
        row.get::<_, &str>("failure_message"),
        "contract retryable failure"
    );
    assert_eq!(row.get::<_, &str>("status"), "failed");

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
async fn db_contracts_requeue_payment_job_resets_exhausted_job() -> Result<()> {
    // Setup the contract database and an exhausted refund job
    let db = contract_tests_db()?;
    let pool = contract_tests_pool()?;
    pool.get()
        .await?
        .execute(
            "
            update payment_job
            set
                attempt_count = 10,
                claim_id = null,
                claimed_at = null,
                failure_message = 'contract exhausted',
                next_attempt_at = current_timestamp,
                status = 'failed'
            where payment_job_id = $1::uuid
            ",
            &[&document_refund_job_id()],
        )
        .await?;

    // Requeue the exhausted job through the Rust wrapper
    db.requeue_payment_job(group_id(), document_refund_job_id()).await?;

    // Check the job is ready for a new automatic attempt cycle
    let row = pool
        .get()
        .await?
        .query_one(
            "
            select attempt_count, failure_message, status
            from payment_job
            where payment_job_id = $1::uuid
            ",
            &[&document_refund_job_id()],
        )
        .await?;
    assert_eq!(row.get::<_, i32>("attempt_count"), 0);
    assert_eq!(row.get::<_, Option<String>>("failure_message"), None);
    assert_eq!(row.get::<_, &str>("status"), "pending");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_requeue_stale_payment_job_claims_releases_old_claims() -> Result<()> {
    // Setup a stale payment job claim beyond the recovery timeout
    let db = contract_tests_db()?;
    let pool = contract_tests_pool()?;
    let claim_id = Uuid::new_v4();
    pool.get()
        .await?
        .execute(
            "
            update payment_job
            set
                attempt_count = 2,
                claim_id = $2::uuid,
                claimed_at = current_timestamp - interval '20 minutes',
                status = 'processing'
            where payment_job_id = $1::uuid
            ",
            &[&document_refund_job_id(), &claim_id],
        )
        .await?;

    // Recover stale claims through the Rust database wrapper
    let recovered = db.requeue_stale_payment_job_claims().await?;

    // Check the stale claim was released without depending on total sweep count
    let row = pool
        .get()
        .await?
        .query_one(
            "
            select claim_id, status
            from payment_job
            where payment_job_id = $1::uuid
            ",
            &[&document_refund_job_id()],
        )
        .await?;
    assert!(recovered >= 1);
    assert_eq!(row.get::<_, Option<Uuid>>("claim_id"), None);
    assert_eq!(row.get::<_, &str>("status"), "failed");

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
