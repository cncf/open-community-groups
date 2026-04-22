-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '73000000-0000-0000-0000-000000000001'
\set eventCategoryID '73000000-0000-0000-0000-000000000002'
\set eventID '73000000-0000-0000-0000-000000000003'
\set eventTicketTypeID '73000000-0000-0000-0000-000000000004'
\set groupCategoryID '73000000-0000-0000-0000-000000000005'
\set groupID '73000000-0000-0000-0000-000000000006'
\set refundPendingPurchaseID '73000000-0000-0000-0000-000000000007'
\set completedPurchaseID '73000000-0000-0000-0000-000000000008'
\set priceWindowID '73000000-0000-0000-0000-000000000009'
\set userID '73000000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'refund-community', 'Refund Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

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
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'eventTicketTypeID', :'eventID', 1, 10, 'General admission');

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

-- Purchases
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

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should record an automatic refund for a refund-pending purchase
select lives_ok(
    $$select record_automatic_refund_for_event_purchase(
        '73000000-0000-0000-0000-000000000007'::uuid,
        're_auto_123'
    )$$,
    'Should record an automatic refund for a refund-pending purchase'
);

-- Should persist the refunded purchase fields
select results_eq(
    $$
        select
            refunded_at is not null,
            status
        from event_purchase
        where event_purchase_id = '73000000-0000-0000-0000-000000000007'::uuid
    $$,
    $$ values (true, 'refunded'::text) $$,
    'Should persist the refunded purchase fields'
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
    $$
        values (
            'event_refunded',
            null::uuid,
            '73000000-0000-0000-0000-000000000001'::uuid,
            '73000000-0000-0000-0000-000000000003'::uuid,
            '73000000-0000-0000-0000-000000000006'::uuid,
            'true',
            '73000000-0000-0000-0000-000000000007',
            're_auto_123',
            '73000000-0000-0000-0000-000000000010'
        )
    $$,
    'Should create the expected automatic refund audit row'
);

-- Should reject purchases that are not refund-pending
select throws_ok(
    $$select record_automatic_refund_for_event_purchase(
        '73000000-0000-0000-0000-000000000008'::uuid,
        're_auto_456'
    )$$,
    'refund-pending purchase not found',
    'Should reject purchases that are not refund-pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
