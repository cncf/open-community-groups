-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '75000000-0000-0000-0000-000000000001'
\set eventCategoryID '75000000-0000-0000-0000-000000000002'
\set eventID '75000000-0000-0000-0000-000000000003'
\set eventTicketTypeID '75000000-0000-0000-0000-000000000004'
\set groupCategoryID '75000000-0000-0000-0000-000000000005'
\set groupID '75000000-0000-0000-0000-000000000006'
\set pendingPurchaseID '75000000-0000-0000-0000-000000000007'
\set approvingPurchaseID '75000000-0000-0000-0000-000000000008'
\set pendingRefundRequestID '75000000-0000-0000-0000-000000000009'
\set approvingRefundRequestID '75000000-0000-0000-0000-000000000010'
\set priceWindowID '75000000-0000-0000-0000-000000000011'
\set user1ID '75000000-0000-0000-0000-000000000012'
\set user2ID '75000000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'refund-start-community', 'Refund Start Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'user1ID', 'hash-1', 'user1@example.com', true, 'buyer-1'),
    (:'user2ID', 'hash-2', 'user2@example.com', true, 'buyer-2');

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

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    provider_payment_reference,
    status,
    ticket_title,
    user_id
) values (
    :'pendingPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'pi_pending',
    'refund-requested',
    'General admission',
    :'user1ID'
), (
    :'approvingPurchaseID',
    3000,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'pi_approving',
    'refund-requested',
    'General admission',
    :'user2ID'
);

-- Refund requests
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
) values (
    :'pendingRefundRequestID',
    :'pendingPurchaseID',
    :'user1ID',
    'pending'
), (
    :'approvingRefundRequestID',
    :'approvingPurchaseID',
    :'user2ID',
    'approving'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should move a pending refund request into approving and return the purchase
select is(
    begin_event_refund_approval(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'user1ID'::uuid
    )::jsonb,
    jsonb_build_object(
        'amount_minor', 2500,
        'currency_code', 'USD',
        'discount_amount_minor', 0,
        'event_purchase_id', :'pendingPurchaseID'::uuid,
        'event_ticket_type_id', :'eventTicketTypeID'::uuid,
        'provider_payment_reference', 'pi_pending',
        'status', 'refund-requested',
        'ticket_title', 'General admission'
    ),
    'Should move a pending refund request into approving and return the purchase'
);

-- Should persist the approving refund request state
select is(
    (
        select status
        from event_refund_request
        where event_refund_request_id = :'pendingRefundRequestID'::uuid
    ),
    'approving',
    'Should persist the approving refund request state'
);

-- Should return already-approving requests without changing them
select is(
    begin_event_refund_approval(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'user2ID'::uuid
    )::jsonb,
    jsonb_build_object(
        'amount_minor', 3000,
        'currency_code', 'USD',
        'discount_amount_minor', 0,
        'event_purchase_id', :'approvingPurchaseID'::uuid,
        'event_ticket_type_id', :'eventTicketTypeID'::uuid,
        'provider_payment_reference', 'pi_approving',
        'status', 'refund-requested',
        'ticket_title', 'General admission'
    ),
    'Should return already-approving requests without changing them'
);

-- Should reject missing refund requests
select throws_ok(
    $$select begin_event_refund_approval(
        '75000000-0000-0000-0000-000000000006'::uuid,
        '75000000-0000-0000-0000-000000000003'::uuid,
        '75000000-0000-0000-0000-000000000099'::uuid
    )$$,
    'refund request not found',
    'Should reject missing refund requests'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
