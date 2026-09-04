-- Tests releasing failed credit-note claims.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set claimID 'd7360000-0000-0000-0000-000000000001'
\set communityID 'd7360000-0000-0000-0000-000000000002'
\set creditNoteID 'd7360000-0000-0000-0000-000000000003'
\set eventCategoryID 'd7360000-0000-0000-0000-000000000004'
\set eventID 'd7360000-0000-0000-0000-000000000005'
\set finalClaimID 'd7360000-0000-0000-0000-000000000013'
\set finalCreditNoteID 'd7360000-0000-0000-0000-000000000014'
\set finalPurchaseID 'd7360000-0000-0000-0000-000000000015'
\set finalRefundID 'd7360000-0000-0000-0000-000000000016'
\set groupCategoryID 'd7360000-0000-0000-0000-000000000006'
\set groupID 'd7360000-0000-0000-0000-000000000007'
\set purchaseID 'd7360000-0000-0000-0000-000000000008'
\set refundID 'd7360000-0000-0000-0000-000000000009'
\set ticketTypeID 'd7360000-0000-0000-0000-000000000010'
\set userID 'd7360000-0000-0000-0000-000000000011'
\set wrongClaimID 'd7360000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with both direct-charge purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('payment_currency_code', 'USD'));

-- Ticket type snapshotted by both purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Refunded purchases owning retryable and final credit-note claims
insert into event_purchase (
    amount_minor, charge_model, connected_seller_id, currency_code, event_id,
    event_purchase_id, event_ticket_type_id, final_platform_fee_amount_minor,
    payment_provider_id, provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_invoice_id, provider_object_account_id,
    provider_payment_reference, provider_total_minor,
    provisional_platform_fee_amount_minor, seller_snapshot, status,
    subtotal_excluding_tax_minor, tax_amount_minor, tax_behavior,
    tax_calculation_mode, tax_classification, ticket_title, user_id,
    venue_snapshot
) values
    (
        2500, 'direct-charge', 'acct_credit', 'USD', :'eventID', :'purchaseID',
        :'ticketTypeID', 100, 'stripe', 'fee_credit', 'ch_credit_credit_note_failure', 'cs_credit_credit_note_failure',
        'in_credit_credit_note_failure', 'acct_credit', 'pi_credit_credit_note_failure', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'userID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_credit', 'USD', :'eventID',
        :'finalPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_credit_final',
        'ch_credit_final', 'cs_credit_final', 'in_credit_final', 'acct_credit',
        'pi_credit_final', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'userID', '{}'::jsonb
    );

-- Successful refunds owning retryable and final credit-note claims
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    idempotency_key, kind, payment_provider_id, provider_refund_id,
    provider_refunded_at, status
) values
    (
        2500, 'USD', :'purchaseID', :'refundID', 'refund-fail-credit-note',
        'automatic-unfulfillable-checkout', 'stripe', 're_credit_credit_note_failure',
        current_timestamp, 'provider-succeeded'
    ),
    (
        2500, 'USD', :'finalPurchaseID', :'finalRefundID',
        'refund-final-credit-note', 'automatic-unfulfillable-checkout',
        'stripe', 're_credit_final', current_timestamp, 'provider-succeeded'
    );

-- Retryable and final-attempt credit-note claims
insert into event_purchase_credit_note (
    amount_minor, attempt_count, claim_id, claimed_at, currency_code,
    event_purchase_credit_note_id, event_purchase_refund_id, idempotency_key,
    payment_provider_id, provider_object_account_id, status, tax_amount_minor
) values
    (
        2500, 1, :'claimID', current_timestamp, 'USD', :'creditNoteID',
        :'refundID', 'fail-credit-note', 'stripe', 'acct_credit',
        'processing', 200
    ),
    (
        2500, 10, :'finalClaimID', current_timestamp, 'USD',
        :'finalCreditNoteID', :'finalRefundID', 'fail-final-credit-note',
        'stripe', 'acct_credit', 'processing', 200
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a stale credit-note failure claim
select throws_ok(
    format(
        'select record_event_purchase_credit_note_failure(%L, %L, %L)',
        :'creditNoteID', :'wrongClaimID', 'wrong claim'
    ),
    'credit-note claim is stale',
    'Should reject a stale credit-note failure claim'
);

-- Should release a failed credit-note claim for retry
select lives_ok(
    format(
        'select record_event_purchase_credit_note_failure(%L, %L, %L)',
        :'creditNoteID', :'claimID', 'temporary provider failure'
    ),
    'Should release a failed credit-note claim for retry'
);

-- Should persist the retryable credit-note failure
select results_eq(
    format($$
        select attempt_count, claim_id, failure_message, status
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'creditNoteID'),
    $$ values (
        1, null::uuid, 'temporary provider failure'::text, 'failed'::text
    ) $$,
    'Should persist the retryable credit-note failure'
);

-- Should release the final automatic credit-note claim for recovery
select lives_ok(
    format(
        'select record_event_purchase_credit_note_failure(%L, %L, %L)',
        :'finalCreditNoteID', :'finalClaimID', 'final provider failure'
    ),
    'Should release the final automatic credit-note claim for recovery'
);

-- Should preserve the exhausted attempt count for operator recovery
select results_eq(
    format($$
        select attempt_count, claim_id, failure_message, status
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'finalCreditNoteID'),
    $$ values (
        10, null::uuid, 'final provider failure'::text, 'failed'::text
    ) $$,
    'Should preserve the exhausted attempt count for operator recovery'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
