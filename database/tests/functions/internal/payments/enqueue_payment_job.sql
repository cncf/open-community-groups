-- Tests enqueueing payment jobs.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd4080000-0000-0000-0000-000000000001'
\set eventCategoryID 'd4080000-0000-0000-0000-000000000002'
\set eventID 'd4080000-0000-0000-0000-000000000003'
\set groupCategoryID 'd4080000-0000-0000-0000-000000000004'
\set groupID 'd4080000-0000-0000-0000-000000000005'
\set purchaseID 'd4080000-0000-0000-0000-000000000006'
\set ticketTypeID 'd4080000-0000-0000-0000-000000000007'
\set userID 'd4080000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, user and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with the purchase
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by the purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Purchase receiving a durable payment job
insert into event_purchase (
    amount_minor, charge_model, connected_seller_id, currency_code, event_id,
    event_purchase_id, event_ticket_type_id, final_platform_fee_amount_minor,
    payment_provider_id, provider_charge_id, provider_checkout_session_id,
    provider_object_account_id, provider_payment_reference,
    provider_total_minor, provisional_platform_fee_amount_minor,
    seller_snapshot, status, subtotal_excluding_tax_minor, tax_amount_minor,
    tax_behavior, tax_calculation_mode, tax_classification, ticket_title,
    user_id, venue_snapshot
) values (
    2500, 'direct-charge', 'acct_d408', 'USD', :'eventID', :'purchaseID',
    :'ticketTypeID', 80, 'stripe', 'ch_enqueue_d4080000',
    'cs_enqueue_d4080000', 'acct_d408', 'pi_enqueue_d4080000', 2500, 100,
    '{"display_name":"Sponsor"}'::jsonb, 'completed', 2300, 200, 'inclusive',
    'manual', 'professional-event-admission', 'General admission', :'userID',
    '{}'::jsonb
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create a pending payment job
select ok(
    enqueue_payment_job(
        'event-purchase-refund',
        'stripe',
        :'purchaseID',
        'enqueue-payment-job-d4080000'
    ) is not null,
    'Should create a pending payment job'
);

-- Should persist the pending payment job
select results_eq(
    $$
        select
            attempt_count,
            event_purchase_id,
            idempotency_key,
            kind,
            payment_provider_id,
            status
        from payment_job
        where idempotency_key = 'enqueue-payment-job-d4080000'
    $$,
    format($$ values (
        0,
        %L::uuid,
        'enqueue-payment-job-d4080000'::text,
        'event-purchase-refund'::text,
        'stripe'::text,
        'pending'::text
    ) $$, :'purchaseID'),
    'Should persist the pending payment job'
);

-- Should return null when the idempotency key already exists
select results_eq(
    format($$
        select
            enqueue_payment_job(
                'event-purchase-refund',
                'stripe',
                %L::uuid,
                'enqueue-payment-job-d4080000'
            ),
            count(*)::int
        from payment_job
        where idempotency_key = 'enqueue-payment-job-d4080000'
    $$, :'purchaseID'),
    $$ values (null::uuid, 1) $$,
    'Should return null when the idempotency key already exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
