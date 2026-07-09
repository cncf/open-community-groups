-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79450000-0000-0000-0000-000000000001'
\set completedPurchaseID '79450000-0000-0000-0000-000000000002'
\set eventCategoryID '79450000-0000-0000-0000-000000000003'
\set eventID '79450000-0000-0000-0000-000000000004'
\set eventTicketTypeID '79450000-0000-0000-0000-000000000005'
\set groupCategoryID '79450000-0000-0000-0000-000000000006'
\set groupID '79450000-0000-0000-0000-000000000007'
\set priceWindowID '79450000-0000-0000-0000-000000000008'
\set refundPendingPurchaseID '79450000-0000-0000-0000-000000000009'
\set refundID '79450000-0000-0000-0000-000000000011'
\set userID '79450000-0000-0000-0000-000000000010'

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
    'refund-community',
    'Refund Community',
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

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'user@example.com', true, 'buyer');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Refund Group', 'refund-group');

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
    'Refund Event',
    'refund-event',
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

-- Purchases in completed and refund-pending states
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
    :'refundPendingPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'userID'
), (
    :'completedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'userID'
);

-- Provider refund record
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status,

    provider_refund_id,
    provider_refunded_at
) values (
    :'refundID',
    2500,
    'USD',
    :'refundPendingPurchaseID',
    'event-purchase-refund-' || :'refundPendingPurchaseID',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-succeeded',

    're_auto_123',
    current_timestamp
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should record an automatic refund for a refund-pending purchase
select lives_ok(
    format($$select record_automatic_refund_for_event_purchase(
        %L::uuid,
        're_auto_123'
    )$$, :'refundPendingPurchaseID'),
    'Should record an automatic refund for a refund-pending purchase'
);

-- Should persist the refunded purchase and refund record fields
select results_eq(
    format($$
        select
            (select refunded_at is not null from event_purchase where event_purchase_id = %L::uuid),
            (select status from event_purchase where event_purchase_id = %L::uuid),
            (select finalized_at is not null from event_purchase_refund where event_purchase_refund_id = %L::uuid),
            (select status from event_purchase_refund where event_purchase_refund_id = %L::uuid)
    $$, :'refundPendingPurchaseID', :'refundPendingPurchaseID', :'refundID', :'refundID'),
    $$ values (true, 'refunded'::text, true, 'finalized'::text) $$,
    'Should persist the refunded purchase and refund record fields'
);

-- Should treat an already finalized automatic refund as a successful retry
select lives_ok(
    format($$select record_automatic_refund_for_event_purchase(
        %L::uuid,
        're_auto_123'
    )$$, :'refundPendingPurchaseID'),
    'Should treat an already finalized automatic refund as a successful retry'
);

-- Should not duplicate the automatic refund audit row on retry
select is(
    (select count(*)::int from audit_log),
    1,
    'Should not duplicate the automatic refund audit row on retry'
);

-- Should create the expected automatic refund audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            community_id,
            event_id,
            group_id,
            details->>'automatic',
            details->>'event_purchase_id',
            details->>'provider_refund_id',
            details->>'user_id'
        from audit_log
    $$,
    format($$
        values (
            'event_refunded',
            null::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'true',
            %L,
            're_auto_123',
            %L
        )
    $$, :'communityID', :'eventID', :'groupID', :'refundPendingPurchaseID', :'userID'),
    'Should create the expected automatic refund audit row'
);

-- Should reject purchases that are not refund-pending
select throws_ok(
    format($$select record_automatic_refund_for_event_purchase(
        %L::uuid,
        're_auto_456'
    )$$, :'completedPurchaseID'),
    'refund-pending purchase not found',
    'Should reject purchases that are not refund-pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
