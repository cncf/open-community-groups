-- Tests claiming provider refund work with retry and terminal-state guards.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd4010000-0000-0000-0000-000000000001'
\set eventCategoryID 'd4010000-0000-0000-0000-000000000002'
\set eventID 'd4010000-0000-0000-0000-000000000003'
\set externalPurchaseID 'd4010000-0000-0000-0000-000000000022'
\set externalUserID 'd4010000-0000-0000-0000-000000000023'
\set exhaustedPurchaseID 'd4010000-0000-0000-0000-000000000004'
\set exhaustedRefundID 'd4010000-0000-0000-0000-000000000005'
\set failedPurchaseID 'd4010000-0000-0000-0000-000000000006'
\set failedRefundID 'd4010000-0000-0000-0000-000000000007'
\set futurePurchaseID 'd4010000-0000-0000-0000-000000000008'
\set futureRefundID 'd4010000-0000-0000-0000-000000000009'
\set groupCategoryID 'd4010000-0000-0000-0000-000000000010'
\set groupID 'd4010000-0000-0000-0000-000000000011'
\set otherProviderPurchaseID 'd4010000-0000-0000-0000-000000000012'
\set otherProviderRefundID 'd4010000-0000-0000-0000-000000000013'
\set pendingPurchaseID 'd4010000-0000-0000-0000-000000000014'
\set pendingRefundID 'd4010000-0000-0000-0000-000000000015'
\set succeededPurchaseID 'd4010000-0000-0000-0000-000000000016'
\set succeededRefundID 'd4010000-0000-0000-0000-000000000017'
\set terminalPurchaseID 'd4010000-0000-0000-0000-000000000018'
\set terminalRefundID 'd4010000-0000-0000-0000-000000000019'
\set ticketTypeID 'd4010000-0000-0000-0000-000000000020'
\set userID 'd4010000-0000-0000-0000-000000000021'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Additional provider used to verify provider-scoped claims
insert into payment_provider (display_name, payment_provider_id)
values ('Other Provider', 'other-provider');

-- Community owning the refund queue fixtures
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.test/mobile.png',
    'https://example.test/banner.png',
    :'communityID',
    'Community',
    'Community',
    'https://example.test/logo.png',
    'claim-refund-community'
);

-- Event category used by the refund queue event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the refund queue group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the refund queue event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- User owning all independent purchase fixtures
insert into "user" (auth_hash, email, user_id, username)
values
    ('user', 'user@example.test', :'userID', 'user'),
    ('external-user', 'external-user@example.test', :'externalUserID', 'external-user');

-- Event owning all independent purchase fixtures
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    slug,
    timezone
) values (
    'Event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Event',
    'USD',
    'event',
    'UTC'
);

-- Ticket type referenced by all independent purchases
insert into event_ticket_type (event_id, event_ticket_type_id, "order", seats_total, title)
values (:'eventID', :'ticketTypeID', 1, 100, 'General admission');

-- Purchases backing due, excluded, and provider-complete refund rows
insert into event_purchase (
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    provisional_platform_fee_amount_minor,
    seller_snapshot,
    status,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
)
select
    2500,
    'direct-charge',
    fixtures.connected_seller_id,
    'USD',
    :'eventID',
    fixtures.event_purchase_id,
    :'ticketTypeID',
    fixtures.platform_fee_amount_minor,
    fixtures.payment_provider_id,
    'ch_' || fixtures.provider_payment_reference,
    'cs_' || fixtures.provider_payment_reference,
    fixtures.connected_seller_id,
    fixtures.provider_payment_reference,
    2500,
    fixtures.platform_fee_amount_minor,
    jsonb_build_object(
        'connected_account_id', fixtures.connected_seller_id,
        'display_name', 'Fiscal Sponsor',
        'provider', fixtures.payment_provider_id
    ),
    fixtures.status,
    2500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'userID',
    '{"address":"1 Main St","city":"Portland","country_code":"US","name":"Venue","state_code":"OR","state_name":"Oregon","zip_code":"97201"}'::jsonb
from (values
    (:'exhaustedPurchaseID'::uuid, 'refund-pending', 'stripe', 'acct_stripe', 0::bigint, 'pi_exhausted'),
    (:'failedPurchaseID'::uuid, 'refund-pending', 'stripe', 'acct_stripe', 0::bigint, 'pi_failed'),
    (:'futurePurchaseID'::uuid, 'refund-pending', 'stripe', 'acct_stripe', 0::bigint, 'pi_future'),
    (:'otherProviderPurchaseID'::uuid, 'refund-pending', 'other-provider', 'acct_other', 0::bigint, 'pi_other'),
    (:'pendingPurchaseID'::uuid, 'refund-pending', 'stripe', 'acct_stripe', 0::bigint, 'pi_pending'),
    (:'succeededPurchaseID'::uuid, 'refund-pending', 'stripe', 'acct_stripe', 250::bigint, 'pi_succeeded'),
    (:'terminalPurchaseID'::uuid, 'refund-recovery-pending', 'stripe', 'acct_stripe', 0::bigint, 'pi_terminal')
) as fixtures (
    event_purchase_id,
    status,
    payment_provider_id,
    connected_seller_id,
    platform_fee_amount_minor,
    provider_payment_reference
);

-- Completed external purchase that must not produce provider refund work
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    'KRW',
    :'eventID',
    :'externalPurchaseID',
    :'ticketTypeID',
    0,
    0,
    'completed',
    'External admission',
    :'externalUserID'
);

-- Refund rows covering priority, retry, scheduling, exhaustion, and provider scoping
insert into event_purchase_refund (
    amount_minor,
    attempt_count,
    created_at,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_provider_id,
    status,
    terminal_failure,

    failure_message,
    provider_refund_id,
    provider_refunded_at
) values
    (2500, 10, '2024-01-04 00:00:00+00', 'USD', :'exhaustedPurchaseID', :'exhaustedRefundID', 'refund-exhausted', 'event-cancellation', '2024-01-04 00:00:00+00', 'stripe', 'provider-pending', false, null, null, null),
    (2500, 3, '2024-01-02 00:00:00+00', 'USD', :'failedPurchaseID', :'failedRefundID', 'refund-failed', 'event-cancellation', '2024-01-02 00:00:00+00', 'stripe', 'provider-failed', false, 'provider unavailable', null, null),
    (2500, 0, '2024-01-05 00:00:00+00', 'USD', :'futurePurchaseID', :'futureRefundID', 'refund-future', 'event-cancellation', '2099-01-01 00:00:00+00', 'stripe', 'provider-pending', false, null, null, null),
    (2500, 0, '2024-01-01 00:00:00+00', 'USD', :'otherProviderPurchaseID', :'otherProviderRefundID', 'refund-other', 'event-cancellation', '2024-01-01 00:00:00+00', 'other-provider', 'provider-pending', false, null, null, null),
    (2500, 0, '2024-01-01 00:00:00+00', 'USD', :'pendingPurchaseID', :'pendingRefundID', 'refund-pending', 'event-cancellation', '2024-01-01 00:00:00+00', 'stripe', 'provider-pending', false, null, null, null),
    (2500, 4, '2024-01-03 00:00:00+00', 'USD', :'succeededPurchaseID', :'succeededRefundID', 'refund-succeeded', 'event-cancellation', '2024-01-03 00:00:00+00', 'stripe', 'provider-succeeded', false, null, 're_succeeded', current_timestamp),
    (2500, 1, '2024-01-06 00:00:00+00', 'USD', :'terminalPurchaseID', :'terminalRefundID', 'refund-terminal', 'event-cancellation', '2024-01-06 00:00:00+00', 'stripe', 'provider-failed', true, 'terminal', 're_terminal', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should claim provider-complete work before provider reconciliation work
select results_eq(
    $$
        select
            result->>'community_id',
            result->>'event_id',
            result->>'event_purchase_refund_id',
            (result->>'attempt_count')::int,
            result->>'provider_payment_reference',
            result->>'provider_refund_id',
            result->>'status'
        from (select claim_event_purchase_refund('stripe')::jsonb as result) claimed
    $$,
    format($$ values (
        %L::text,
        %L::text,
        %L::text,
        4,
        'pi_succeeded'::text,
        're_succeeded'::text,
        'processing'::text
    ) $$, :'communityID', :'eventID', :'succeededRefundID'),
    'Should claim provider-complete work with its notification context'
);

-- Should persist a claim without incrementing provider-complete attempts
select results_eq(
    format($$
        select attempt_count, claim_id is not null, claimed_at is not null, status
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'succeededRefundID'),
    $$ values (4, true, true, 'processing'::text) $$,
    'Should persist a claim without incrementing provider-complete attempts'
);

-- Should claim due pending work and increment its attempt count
select results_eq(
    $$
        select
            result->>'event_purchase_refund_id',
            (result->>'attempt_count')::int,
            result->>'status'
        from (select claim_event_purchase_refund('stripe')::jsonb as result) claimed
    $$,
    format($$ values (%L::text, 1, 'processing'::text) $$, :'pendingRefundID'),
    'Should claim due pending work and increment its attempt count'
);

-- Should claim due retryable failure work and increment its attempt count
select results_eq(
    $$
        select
            result->>'event_purchase_refund_id',
            (result->>'attempt_count')::int,
            result->>'status'
        from (select claim_event_purchase_refund('stripe')::jsonb as result) claimed
    $$,
    format($$ values (%L::text, 4, 'processing'::text) $$, :'failedRefundID'),
    'Should claim due retryable failure work and increment its attempt count'
);

-- Should return no work after every eligible refund is claimed
select is(
    claim_event_purchase_refund('stripe')::jsonb,
    null::jsonb,
    'Should return no work after every eligible refund is claimed'
);

-- Should leave future, exhausted, terminal, and other-provider work unclaimed
select results_eq(
    format($$
        select event_purchase_refund_id, claim_id, status
        from event_purchase_refund
        where event_purchase_refund_id in (%L::uuid, %L::uuid, %L::uuid, %L::uuid)
        order by event_purchase_refund_id
    $$, :'exhaustedRefundID', :'futureRefundID', :'otherProviderRefundID', :'terminalRefundID'),
    format($$ values
        (%L::uuid, null::uuid, 'provider-pending'::text),
        (%L::uuid, null::uuid, 'provider-pending'::text),
        (%L::uuid, null::uuid, 'provider-pending'::text),
        (%L::uuid, null::uuid, 'provider-failed'::text)
    $$, :'exhaustedRefundID', :'futureRefundID', :'otherProviderRefundID', :'terminalRefundID'),
    'Should leave future, exhausted, terminal, and other-provider work unclaimed'
);

-- Should keep provider refund claims isolated from external purchases
select is(
    (
        select count(*)::int
        from event_purchase_refund
        where event_purchase_id = :'externalPurchaseID'::uuid
    ),
    0,
    'Should keep provider refund claims isolated from external purchases'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
