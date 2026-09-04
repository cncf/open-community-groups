-- Tests completing credit-note claims.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set claimID 'd7370000-0000-0000-0000-000000000001'
\set communityID 'd7370000-0000-0000-0000-000000000002'
\set creditNoteID 'd7370000-0000-0000-0000-000000000003'
\set eventCategoryID 'd7370000-0000-0000-0000-000000000004'
\set eventID 'd7370000-0000-0000-0000-000000000005'
\set groupCategoryID 'd7370000-0000-0000-0000-000000000006'
\set groupID 'd7370000-0000-0000-0000-000000000007'
\set purchaseID 'd7370000-0000-0000-0000-000000000008'
\set refundID 'd7370000-0000-0000-0000-000000000009'
\set ticketTypeID 'd7370000-0000-0000-0000-000000000010'
\set userID 'd7370000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with the refunded purchase
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('payment_currency_code', 'USD'));

-- Ticket type snapshotted by the purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Refunded direct-charge purchase with a durable invoice
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
) values (
    2500, 'direct-charge', 'acct_credit', 'USD', :'eventID', :'purchaseID',
    :'ticketTypeID', 100, 'stripe', 'fee_credit', 'ch_credit_credit_note_succeeded', 'cs_credit_credit_note_succeeded',
    'in_credit_credit_note_succeeded', 'acct_credit', 'pi_credit_credit_note_succeeded', 2500, 100,
    '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded', 2300, 200,
    'inclusive', 'manual', 'professional-event-admission', 'General admission',
    :'userID', '{}'::jsonb
);

-- Successful provider refund awaiting its credit note
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    idempotency_key, kind, payment_provider_id, provider_refund_id,
    provider_refunded_at, status
) values (
    2500, 'USD', :'purchaseID', :'refundID', 'refund-complete-credit-note',
    'automatic-unfulfillable-checkout', 'stripe', 're_credit_credit_note_succeeded', current_timestamp,
    'provider-succeeded'
);

-- Processing credit-note claim
insert into event_purchase_credit_note (
    amount_minor, attempt_count, claim_id, claimed_at, currency_code,
    event_purchase_credit_note_id, event_purchase_refund_id, idempotency_key,
    payment_provider_id, provider_object_account_id, status, tax_amount_minor
) values (
    2500, 1, :'claimID', current_timestamp, 'USD', :'creditNoteID', :'refundID',
    'complete-credit-note', 'stripe', 'acct_credit', 'processing', 200
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should complete a claimed credit note
select lives_ok(
    format(
        'select record_event_purchase_credit_note_succeeded(%L, %L, %L, %L, %L)',
        :'creditNoteID', :'claimID', 'cn_credit',
        'https://credit.test/one', 'https://credit.test/one.pdf'
    ),
    'Should complete a claimed credit note'
);

-- Should persist the issued credit note and current URLs
select results_eq(
    format($$
        select provider_credit_note_id, provider_hosted_url,
            provider_pdf_url, status
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'creditNoteID'),
    $$ values (
        'cn_credit'::text,
        'https://credit.test/one'::text,
        'https://credit.test/one.pdf'::text,
        'issued'::text
    ) $$,
    'Should persist the issued credit note and current URLs'
);

-- Should accept an idempotent credit-note completion replay
select lives_ok(
    format(
        'select record_event_purchase_credit_note_succeeded(%L, %L, %L, null, null)',
        :'creditNoteID', :'claimID', 'cn_credit'
    ),
    'Should accept an idempotent credit-note completion replay'
);

-- Should reject a conflicting credit-note completion replay
select throws_ok(
    format(
        'select record_event_purchase_credit_note_succeeded(%L, %L, %L, null, null)',
        :'creditNoteID', :'claimID', 'cn_other'
    ),
    'credit note has a different provider id',
    'Should reject a conflicting credit-note completion replay'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
