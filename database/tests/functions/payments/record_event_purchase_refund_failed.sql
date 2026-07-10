-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79500000-0000-0000-0000-000000000001'
\set eventCategoryID '79500000-0000-0000-0000-000000000002'
\set eventID '79500000-0000-0000-0000-000000000003'
\set eventTicketTypeID '79500000-0000-0000-0000-000000000004'
\set failedPurchaseID '79500000-0000-0000-0000-000000000005'
\set failedRefundID '79500000-0000-0000-0000-000000000006'
\set failedUserID '79500000-0000-0000-0000-000000000007'
\set finalizedPurchaseID '79500000-0000-0000-0000-000000000015'
\set finalizedRefundID '79500000-0000-0000-0000-000000000016'
\set finalizedUserID '79500000-0000-0000-0000-000000000017'
\set groupCategoryID '79500000-0000-0000-0000-000000000008'
\set groupID '79500000-0000-0000-0000-000000000009'
\set missingRefundID '79500000-0000-0000-0000-000000000014'
\set priceWindowID '79500000-0000-0000-0000-000000000010'
\set succeededPurchaseID '79500000-0000-0000-0000-000000000011'
\set succeededRefundID '79500000-0000-0000-0000-000000000012'
\set succeededUserID '79500000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'record-refund-failure-community',
    'Record Refund Failure Community',
    'Test',
    'https://e/banner-mobile.png',
    'https://e/banner.png',
    'https://e/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Buyers for the pending, finalized, and succeeded refund scenarios
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'failedUserID', 'hash-1', 'failed-buyer@example.com', true, 'failed-buyer'),
    (
        :'finalizedUserID',
        'hash-3',
        'finalized-buyer@example.com',
        true,
        'finalized-buyer'
    ),
    (
        :'succeededUserID',
        'hash-2',
        'succeeded-buyer@example.com',
        true,
        'succeeded-buyer'
    );

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Record Refund Failure Group',
    'record-refund-failure-group'
);

-- Event
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    starts_at,
    published,
    published_at
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Record Refund Failure Event',
    'record-refund-failure-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    true,
    now()
);

-- Ticket type
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'eventTicketTypeID',
    :'eventID',
    1,
    10,
    'General admission'
);

-- Price window
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    2500,
    :'eventTicketTypeID'
);

-- Purchases for the pending, finalized, and succeeded refund scenarios
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'failedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'failedUserID'
), (
    :'finalizedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refunded',
    'General admission',
    :'finalizedUserID'
), (
    :'succeededPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'succeededUserID'
);

-- Provider records for the pending, finalized, and succeeded refund scenarios
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status,

    finalized_at,
    provider_refund_id,
    provider_refunded_at
) values (
    :'failedRefundID',
    2500,
    'USD',
    :'failedPurchaseID',
    'event-purchase-refund-' || :'failedPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-pending',

    null,
    null,
    null
), (
    :'finalizedRefundID',
    2500,
    'USD',
    :'finalizedPurchaseID',
    'event-purchase-refund-' || :'finalizedPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'finalized',

    current_timestamp,
    're_finalized_123',
    current_timestamp
), (
    :'succeededRefundID',
    2500,
    'USD',
    :'succeededPurchaseID',
    'event-purchase-refund-' || :'succeededPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-succeeded',

    null,
    're_success_123',
    current_timestamp
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should record provider refund failure on a pending refund row
select lives_ok(
    format($$select record_event_purchase_refund_failed(
        %L::uuid,
        '  provider timeout  '
    )$$, :'failedRefundID'),
    'Should record provider refund failure on a pending refund row'
);

-- Should persist the provider failure state
select results_eq(
    format($$
        select status, failure_message
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'failedRefundID'),
    $$ values ('provider-failed'::text, 'provider timeout'::text) $$,
    'Should persist the provider failure state'
);

-- Should not downgrade a refund row after provider success is recorded
select lives_ok(
    format($$select record_event_purchase_refund_failed(
        %L::uuid,
        'provider timeout'
    )$$, :'succeededRefundID'),
    'Should not downgrade a refund row after provider success is recorded'
);

-- Should keep the successful provider refund state
select results_eq(
    format($$
        select status, provider_refund_id, failure_message
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'succeededRefundID'),
    $$ values ('provider-succeeded'::text, 're_success_123'::text, null::text) $$,
    'Should keep the successful provider refund state'
);

-- Should not downgrade a locally finalized refund row
select lives_ok(
    format($$select record_event_purchase_refund_failed(
        %L::uuid,
        'provider timeout'
    )$$, :'finalizedRefundID'),
    'Should not downgrade a locally finalized refund row'
);

-- Should keep the locally finalized refund state
select results_eq(
    format($$
        select status, failure_message
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'finalizedRefundID'),
    $$ values ('finalized'::text, null::text) $$,
    'Should keep the locally finalized refund state'
);

-- Should reject missing refund rows
select throws_ok(
    format($$select record_event_purchase_refund_failed(
        %L::uuid,
        'provider timeout'
    )$$, :'missingRefundID'),
    'event purchase refund not found',
    'Should reject missing refund rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
