-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79480000-0000-0000-0000-000000000001'
\set durablePurchaseID '79480000-0000-0000-0000-000000000013'
\set durableRefundID '79480000-0000-0000-0000-000000000014'
\set durableRefundRequestID '79480000-0000-0000-0000-000000000015'
\set eventCategoryID '79480000-0000-0000-0000-000000000002'
\set eventID '79480000-0000-0000-0000-000000000003'
\set eventTicketTypeID '79480000-0000-0000-0000-000000000004'
\set groupCategoryID '79480000-0000-0000-0000-000000000005'
\set groupID '79480000-0000-0000-0000-000000000006'
\set otherGroupID '79480000-0000-0000-0000-000000000007'
\set otherUserID '79480000-0000-0000-0000-000000000008'
\set priceWindowID '79480000-0000-0000-0000-000000000009'
\set purchaseID '79480000-0000-0000-0000-000000000010'
\set refundRequestID '79480000-0000-0000-0000-000000000011'
\set userID '79480000-0000-0000-0000-000000000012'

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
    'revert-community',
    'Revert Community',
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

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (
        :'otherUserID',
        'hash-2',
        'user2@example.com',
        true,
        'other'
    ),
    (
        :'userID',
        'hash-1',
        'user1@example.com',
        true,
        'buyer'
    );

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug)
values
    (
        :'groupID',
        :'communityID',
        :'groupCategoryID',
        'Refund Group',
        'refund-group'
    ),
    (
        :'otherGroupID',
        :'communityID',
        :'groupCategoryID',
        'Other Group',
        'other-group'
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

-- Purchases for the revertible and durable approval scenarios
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values
    (
        :'durablePurchaseID',
        2500,
        'USD',
        :'eventID',
        :'eventTicketTypeID',
        'refund-requested',
        'General admission',
        :'otherUserID'
    ),
    (
        :'purchaseID',
        2500,
        'USD',
        :'eventID',
        :'eventTicketTypeID',
        'refund-requested',
        'General admission',
        :'userID'
    );

-- Refund requests for the revertible and durable approval scenarios
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
) values
    (
        :'durableRefundRequestID',
        :'durablePurchaseID',
        :'otherUserID',
        'approving'
    ),
    (
        :'refundRequestID',
        :'purchaseID',
        :'userID',
        'approving'
    );

-- Durable provider handoff that protects its approving refund request
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status,

    event_refund_request_id
) values (
    :'durableRefundID',
    2500,
    'USD',
    :'durablePurchaseID',
    'event-purchase-refund-' || :'durablePurchaseID',
    'refund-request-approval',
    'stripe',
    'provider-pending',

    :'durableRefundRequestID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should move an approving refund request back to pending
select lives_ok(
    format($$select revert_event_refund_approval(
        %L::uuid,
        %L::uuid,
        %L::uuid
    )$$, :'groupID', :'eventID', :'userID'),
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

-- Should preserve an approving request after its durable refund handoff
select lives_ok(
    format($$select revert_event_refund_approval(
        %L::uuid,
        %L::uuid,
        %L::uuid
    )$$, :'groupID', :'eventID', :'otherUserID'),
    'Should preserve an approving request after its durable refund handoff'
);

-- Should leave the durable refund request approving
select is(
    (
        select status
        from event_refund_request
        where event_refund_request_id = :'durableRefundRequestID'::uuid
    ),
    'approving',
    'Should leave the durable refund request approving'
);

-- Should ignore requests outside the selected scope
select lives_ok(
    format($$select revert_event_refund_approval(
        %L::uuid,
        %L::uuid,
        %L::uuid
    )$$, :'otherGroupID', :'eventID', :'otherUserID'),
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
