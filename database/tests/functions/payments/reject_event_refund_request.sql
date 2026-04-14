-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '77000000-0000-0000-0000-000000000001'
\set communityID '77000000-0000-0000-0000-000000000002'
\set eventCategoryID '77000000-0000-0000-0000-000000000003'
\set eventID '77000000-0000-0000-0000-000000000004'
\set eventTicketTypeID '77000000-0000-0000-0000-000000000005'
\set groupCategoryID '77000000-0000-0000-0000-000000000006'
\set groupID '77000000-0000-0000-0000-000000000007'
\set priceWindowID '77000000-0000-0000-0000-000000000008'
\set purchaseID '77000000-0000-0000-0000-000000000009'
\set refundRequestID '77000000-0000-0000-0000-000000000010'
\set userID '77000000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'reject-community', 'Reject Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'actorUserID', 'hash-1', 'actor@example.com', true, 'reviewer'),
    (:'userID', 'hash-2', 'buyer@example.com', true, 'buyer');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Reject Group', 'reject-group');

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
    'Reject Event',
    'reject-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    true,
    now()
);

-- Ticket type and price window
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'eventTicketTypeID', :'eventID', 1, 10, 'General admission');

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    2500,
    :'eventTicketTypeID'
);

-- Purchase and refund request
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
    :'purchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'refund-requested',
    'General admission',
    :'userID'
);

insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
) values (
    :'refundRequestID',
    :'purchaseID',
    :'userID',
    'pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a pending refund request
select is(
    reject_event_refund_request(
        :'actorUserID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'userID'::uuid,
        'Not eligible'
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'user_id', :'userID'::uuid
    ),
    'Should reject a pending refund request'
);

-- Should persist the updated purchase and refund request fields
select results_eq(
    $$
        select
            (select status from event_purchase where event_purchase_id = '77000000-0000-0000-0000-000000000009'::uuid),
            (select review_note from event_refund_request where event_refund_request_id = '77000000-0000-0000-0000-000000000010'::uuid),
            (select reviewed_at is not null from event_refund_request where event_refund_request_id = '77000000-0000-0000-0000-000000000010'::uuid),
            (select reviewed_by_user_id from event_refund_request where event_refund_request_id = '77000000-0000-0000-0000-000000000010'::uuid),
            (select status from event_refund_request where event_refund_request_id = '77000000-0000-0000-0000-000000000010'::uuid)
    $$,
    $$ values ('completed'::text, 'Not eligible'::text, true, '77000000-0000-0000-0000-000000000001'::uuid, 'rejected'::text) $$,
    'Should persist the updated purchase and refund request fields'
);

-- Should create the expected rejection audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            community_id,
            event_id,
            group_id,
            details->>'event_purchase_id',
            details->>'user_id'
        from audit_log
    $$,
    $$ values (
        'event_refund_rejected'::text,
        '77000000-0000-0000-0000-000000000001'::uuid,
        '77000000-0000-0000-0000-000000000002'::uuid,
        '77000000-0000-0000-0000-000000000004'::uuid,
        '77000000-0000-0000-0000-000000000007'::uuid,
        '77000000-0000-0000-0000-000000000009',
        '77000000-0000-0000-0000-000000000011'
    ) $$,
    'Should create the expected rejection audit row'
);

-- Should reject missing pending refund requests
select throws_ok(
    $$select reject_event_refund_request(
        '77000000-0000-0000-0000-000000000001'::uuid,
        '77000000-0000-0000-0000-000000000007'::uuid,
        '77000000-0000-0000-0000-000000000004'::uuid,
        '77000000-0000-0000-0000-000000000099'::uuid,
        null
    )$$,
    'refund request not found',
    'Should reject missing pending refund requests'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
