-- Tests requeueing exhausted credit notes.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd7410000-0000-0000-0000-000000000001'
\set creditNoteID 'd7410000-0000-0000-0000-000000000002'
\set eventCategoryID 'd7410000-0000-0000-0000-000000000003'
\set eventID 'd7410000-0000-0000-0000-000000000004'
\set groupCategoryID 'd7410000-0000-0000-0000-000000000005'
\set groupID 'd7410000-0000-0000-0000-000000000006'
\set lowCreditNoteID 'd7410000-0000-0000-0000-000000000011'
\set lowPurchaseID 'd7410000-0000-0000-0000-000000000012'
\set lowRefundID 'd7410000-0000-0000-0000-000000000013'
\set missingCreditNoteID 'd7410000-0000-0000-0000-000000000014'
\set missingGroupID 'd7410000-0000-0000-0000-000000000015'
\set pendingCreditNoteID 'd7410000-0000-0000-0000-000000000016'
\set pendingPurchaseID 'd7410000-0000-0000-0000-000000000017'
\set pendingRefundID 'd7410000-0000-0000-0000-000000000018'
\set purchaseID 'd7410000-0000-0000-0000-000000000007'
\set refundID 'd7410000-0000-0000-0000-000000000008'
\set ticketTypeID 'd7410000-0000-0000-0000-000000000009'
\set userID 'd7410000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with the refunded purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('payment_currency_code', 'USD'));

-- Ticket type snapshotted by each purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Refunded purchases owning exhausted and ineligible credit notes
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
        :'ticketTypeID', 100, 'stripe', 'fee_credit', 'ch_credit_credit_note_requeue', 'cs_credit_credit_note_requeue',
        'in_credit_credit_note_requeue', 'acct_credit', 'pi_credit_credit_note_requeue', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'userID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_credit', 'USD', :'eventID',
        :'lowPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_low', 'ch_low_credit_note_requeue',
        'cs_low_credit_note_requeue', 'in_low_credit_note_requeue', 'acct_credit', 'pi_low_credit_note_requeue', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'userID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_credit', 'USD', :'eventID',
        :'pendingPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_pending',
        'ch_pending_credit_note_requeue', 'cs_pending_credit_note_requeue', 'in_pending_credit_note_requeue', 'acct_credit', 'pi_pending_credit_note_requeue',
        2500, 100, '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded',
        2300, 200, 'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'userID', '{}'::jsonb
    );

-- Successful refunds owning exhausted and ineligible credit notes
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    idempotency_key, kind, payment_provider_id, provider_refund_id,
    provider_refunded_at, status
) values
    (
        2500, 'USD', :'purchaseID', :'refundID', 'refund-requeue-credit-note',
        'automatic-unfulfillable-checkout', 'stripe', 're_credit_credit_note_requeue',
        current_timestamp, 'provider-succeeded'
    ),
    (
        2500, 'USD', :'lowPurchaseID', :'lowRefundID',
        'refund-requeue-low-credit-note', 'automatic-unfulfillable-checkout',
        'stripe', 're_low_credit_note_requeue', current_timestamp, 'provider-succeeded'
    ),
    (
        2500, 'USD', :'pendingPurchaseID', :'pendingRefundID',
        'refund-requeue-pending-credit-note',
        'automatic-unfulfillable-checkout', 'stripe', 're_pending_credit_note_requeue',
        current_timestamp, 'provider-succeeded'
    );

-- Exhausted, under-budget, and wrong-status credit notes
insert into event_purchase_credit_note (
    amount_minor, attempt_count, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, failure_message, idempotency_key,
    payment_provider_id, provider_object_account_id, status, tax_amount_minor
) values
    (
        2500, 10, 'USD', :'creditNoteID', :'refundID',
        'automatic attempts exhausted', 'requeue-credit-note', 'stripe',
        'acct_credit', 'failed', 200
    ),
    (
        2500, 9, 'USD', :'lowCreditNoteID', :'lowRefundID',
        'provider unavailable', 'requeue-low-credit-note', 'stripe',
        'acct_credit', 'failed', 200
    ),
    (
        2500, 10, 'USD', :'pendingCreditNoteID', :'pendingRefundID', null,
        'requeue-pending-credit-note', 'stripe', 'acct_credit', 'pending', 200
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a missing credit note
select throws_ok(
    format(
        'select requeue_event_purchase_credit_note(%L, %L)',
        :'groupID', :'missingCreditNoteID'
    ),
    'OCG01',
    'retryable credit note not found',
    'Should reject a missing credit note'
);

-- Should reject a credit note from another group
select throws_ok(
    format(
        'select requeue_event_purchase_credit_note(%L, %L)',
        :'missingGroupID', :'creditNoteID'
    ),
    'OCG01',
    'retryable credit note not found',
    'Should reject a credit note from another group'
);

-- Should reject credit-note work before automatic retries are exhausted
select throws_ok(
    format(
        'select requeue_event_purchase_credit_note(%L, %L)',
        :'groupID', :'lowCreditNoteID'
    ),
    'OCG01',
    'retryable credit note not found',
    'Should reject credit-note work before automatic retries are exhausted'
);

-- Should reject credit-note work with a non-failed status
select throws_ok(
    format(
        'select requeue_event_purchase_credit_note(%L, %L)',
        :'groupID', :'pendingCreditNoteID'
    ),
    'OCG01',
    'retryable credit note not found',
    'Should reject credit-note work with a non-failed status'
);

-- Should requeue an exhausted credit note
select lives_ok(
    format(
        'select requeue_event_purchase_credit_note(%L, %L)',
        :'groupID', :'creditNoteID'
    ),
    'Should requeue an exhausted credit note'
);

-- Should reset credit-note work for another bounded attempt cycle
select results_eq(
    format($$
        select attempt_count, failure_message, status
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'creditNoteID'),
    $$ values (0, null::text, 'pending'::text) $$,
    'Should reset credit-note work for another bounded attempt cycle'
);

-- Should preserve every rejected credit-note work item
select results_eq(
    format($$
        select event_purchase_credit_note_id, attempt_count, status
        from event_purchase_credit_note
        where event_purchase_credit_note_id in (%L::uuid, %L::uuid)
        order by event_purchase_credit_note_id
    $$, :'lowCreditNoteID', :'pendingCreditNoteID'),
    format(
        $$ values
            (%L::uuid, 9, 'failed'::text),
            (%L::uuid, 10, 'pending'::text)
        $$,
        :'lowCreditNoteID', :'pendingCreditNoteID'
    ),
    'Should preserve every rejected credit-note work item'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
