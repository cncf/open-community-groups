-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '74000000-0000-0000-0000-000000000001'
\set eventCategoryID '74000000-0000-0000-0000-000000000002'
\set eventID '74000000-0000-0000-0000-000000000003'
\set eventTicketTypeID '74000000-0000-0000-0000-000000000004'
\set groupCategoryID '74000000-0000-0000-0000-000000000005'
\set groupID '74000000-0000-0000-0000-000000000006'
\set otherGroupID '74000000-0000-0000-0000-000000000007'
\set otherUserID '74000000-0000-0000-0000-000000000008'
\set priceWindowID '74000000-0000-0000-0000-000000000009'
\set purchaseID '74000000-0000-0000-0000-000000000010'
\set refundRequestID '74000000-0000-0000-0000-000000000011'
\set userID '74000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'revert-community', 'Revert Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'userID', 'hash-1', 'user1@example.com', true, 'buyer'),
    (:'otherUserID', 'hash-2', 'user2@example.com', true, 'other');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'groupID', :'communityID', :'groupCategoryID', 'Refund Group', 'refund-group'),
    (:'otherGroupID', :'communityID', :'groupCategoryID', 'Other Group', 'other-group');

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

-- Ticket price window
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

-- Event refund request
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
) values (
    :'refundRequestID',
    :'purchaseID',
    :'userID',
    'approving'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should move an approving refund request back to pending
select lives_ok(
    $$select revert_event_refund_approval(
        '74000000-0000-0000-0000-000000000006'::uuid,
        '74000000-0000-0000-0000-000000000003'::uuid,
        '74000000-0000-0000-0000-000000000012'::uuid
    )$$,
    'Should move an approving refund request back to pending'
);

-- Should update the refund request status to pending
select is(
    (
        select status
        from event_refund_request
        where event_refund_request_id = :'refundRequestID'::uuid
    ),
    'pending',
    'Should update the refund request status to pending'
);

-- Should ignore requests outside the selected scope
select lives_ok(
    $$select revert_event_refund_approval(
        '74000000-0000-0000-0000-000000000007'::uuid,
        '74000000-0000-0000-0000-000000000003'::uuid,
        '74000000-0000-0000-0000-000000000008'::uuid
    )$$,
    'Should ignore requests outside the selected scope'
);

-- Should leave the refund request pending after ignored updates
select is(
    (
        select status
        from event_refund_request
        where event_refund_request_id = :'refundRequestID'::uuid
    ),
    'pending',
    'Should leave the refund request pending after ignored updates'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
