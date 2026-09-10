-- Tests recording credit-note provider outcomes.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd4030000-0000-0000-0000-000000000001'
\set creditNoteID 'd4030000-0000-0000-0000-000000000002'
\set eventCategoryID 'd4030000-0000-0000-0000-000000000003'
\set eventID 'd4030000-0000-0000-0000-000000000004'
\set groupCategoryID 'd4030000-0000-0000-0000-000000000005'
\set groupID 'd4030000-0000-0000-0000-000000000006'
\set jobID 'd4030000-0000-0000-0000-000000000007'
\set purchaseID 'd4030000-0000-0000-0000-000000000008'
\set refundID 'd4030000-0000-0000-0000-000000000009'
\set refundJobID 'd4030000-0000-0000-0000-000000000010'
\set ticketTypeID 'd4030000-0000-0000-0000-000000000011'
\set userID 'd4030000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, user and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with the refunded purchase
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by the purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Refunded direct-charge purchase owning the credit note
insert into event_purchase (
    amount_minor, charge_model, completed_at, connected_seller_id,
    currency_code, event_id, event_purchase_id, event_ticket_type_id,
    final_platform_fee_amount_minor, payment_provider_id,
    provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_invoice_id,
    provider_object_account_id, provider_payment_reference,
    provider_total_minor, provisional_platform_fee_amount_minor,
    seller_snapshot, status, subtotal_excluding_tax_minor, tax_amount_minor,
    tax_behavior, tax_calculation_mode, tax_classification, ticket_title,
    user_id, venue_snapshot
) values (
    2500, 'direct-charge', current_timestamp, 'acct_d403', 'USD', :'eventID',
    :'purchaseID', :'ticketTypeID', 100, 'stripe', 'fee_credit_d4030000',
    'ch_credit_d4030000', 'cs_credit_d4030000', 'in_credit_d4030000',
    'acct_d403', 'pi_credit_d4030000', 2500, 100,
    '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive',
    'manual', 'professional-event-admission', 'General admission', :'userID',
    '{}'::jsonb
);

-- Payment job for the already-confirmed refund
insert into payment_job (
    completed_at, event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id, status
) values (
    current_timestamp, :'purchaseID',
    'apply-credit-note-outcome-refund-d4030000', 'event-purchase-refund',
    :'refundJobID', 'stripe', 'completed'
);

-- Provider-confirmed refund documented by the credit note
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    finalized_at, kind, payment_job_id, payment_provider_id,
    provider_refund_id, provider_refunded_at, status, terminal_failure
) values (
    2500, 'USD', :'purchaseID', :'refundID', current_timestamp,
    'automatic-unfulfillable-checkout', :'refundJobID', 'stripe',
    're_credit_d4030000', current_timestamp, 'finalized', false
);

-- Payment job for the credit note
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'purchaseID', 'apply-credit-note-outcome-d4030000',
    'event-purchase-credit-note', :'jobID', 'stripe'
);

-- Credit note awaiting provider outcome
insert into event_purchase_credit_note (
    amount_minor, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, payment_job_id, payment_provider_id,
    provider_object_account_id, tax_amount_minor
) values (
    2500, 'USD', :'creditNoteID', :'refundID', :'jobID', 'stripe',
    'acct_d403', 200
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should record provider identity and normalized document URLs
select lives_ok(
    format($$
        select apply_event_purchase_credit_note_outcome(
            epcn,
            'cn_d4030000',
            '  https://stripe.test/hosted/d4030000  ',
            '   '
        )
        from event_purchase_credit_note epcn
        where epcn.event_purchase_credit_note_id = %L::uuid
    $$, :'creditNoteID'),
    'Should record provider identity and normalized document URLs'
);
select results_eq(
    format($$
        select
            provider_credit_note_id,
            provider_hosted_url,
            provider_pdf_url
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'creditNoteID'),
    $$ values (
        'cn_d4030000'::text,
        'https://stripe.test/hosted/d4030000'::text,
        null::text
    ) $$,
    'Should persist provider identity and normalized document URLs'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
