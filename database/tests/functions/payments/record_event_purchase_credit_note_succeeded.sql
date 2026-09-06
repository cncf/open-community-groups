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
\set creditNoteJobID 'd7370000-0000-0000-0000-000000000012'
\set eventCategoryID 'd7370000-0000-0000-0000-000000000004'
\set eventID 'd7370000-0000-0000-0000-000000000005'
\set groupCategoryID 'd7370000-0000-0000-0000-000000000006'
\set groupID 'd7370000-0000-0000-0000-000000000007'
\set purchaseID 'd7370000-0000-0000-0000-000000000008'
\set refundID 'd7370000-0000-0000-0000-000000000009'
\set refundJobID 'd7370000-0000-0000-0000-000000000013'
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

-- Payment job for the successful provider refund
insert into payment_job (
    payment_job_id, event_purchase_id, idempotency_key, kind,
    payment_provider_id
) values (
    :'refundJobID', :'purchaseID',
    'refund-complete-credit-note-succeeded-refund-job',
    'event-purchase-refund', 'stripe'
);

-- Successful provider refund awaiting its credit note
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, provider_refund_id,
    provider_refunded_at, status
) values (
    2500, 'USD', :'purchaseID', :'refundID',
    'automatic-unfulfillable-checkout', :'refundJobID', 'stripe',
    're_credit_credit_note_succeeded', current_timestamp,
    'provider-succeeded'
);

-- Processing payment job for the credit-note claim
insert into payment_job (
    payment_job_id, attempt_count, event_purchase_id, idempotency_key,
    kind, payment_provider_id, status,

    claim_id, claimed_at
) values (
    :'creditNoteJobID', 1, :'purchaseID',
    'complete-credit-note-succeeded-job',
    'event-purchase-credit-note', 'stripe', 'processing',

    :'claimID', current_timestamp
);

-- Processing credit note pinned to the job
insert into event_purchase_credit_note (
    event_purchase_credit_note_id, amount_minor, currency_code,
    event_purchase_refund_id, payment_job_id, payment_provider_id,
    provider_object_account_id, tax_amount_minor
) values (
    :'creditNoteID', 2500, 'USD', :'refundID', :'creditNoteJobID',
    'stripe', 'acct_credit', 200
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
        select
            epcn.provider_credit_note_id,
            epcn.provider_hosted_url,
            epcn.provider_pdf_url,
            pj.status,
            pj.completed_at is not null
        from event_purchase_credit_note epcn
        join payment_job pj using (payment_job_id)
        where event_purchase_credit_note_id = %L::uuid
    $$, :'creditNoteID'),
    $$ values (
        'cn_credit'::text,
        'https://credit.test/one'::text,
        'https://credit.test/one.pdf'::text,
        'completed'::text,
        true
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
