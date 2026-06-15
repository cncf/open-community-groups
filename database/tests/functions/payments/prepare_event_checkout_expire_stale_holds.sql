-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activePurchaseID '79220000-0000-0000-0000-000000000014'
\set communityID '79220000-0000-0000-0000-000000000001'
\set discountCodeID '79220000-0000-0000-0000-000000000002'
\set eventCategoryID '79220000-0000-0000-0000-000000000003'
\set eventID '79220000-0000-0000-0000-000000000004'
\set groupCategoryID '79220000-0000-0000-0000-000000000008'
\set groupID '79220000-0000-0000-0000-000000000009'
\set otherEventID '79220000-0000-0000-0000-000000000005'
\set otherEventPurchaseID '79220000-0000-0000-0000-000000000015'
\set otherPriceWindowID '79220000-0000-0000-0000-000000000011'
\set otherTicketTypeID '79220000-0000-0000-0000-000000000007'
\set priceWindowID '79220000-0000-0000-0000-000000000010'
\set stalePurchaseAID '79220000-0000-0000-0000-000000000012'
\set stalePurchaseBID '79220000-0000-0000-0000-000000000013'
\set ticketTypeID '79220000-0000-0000-0000-000000000006'
\set user1ID '79220000-0000-0000-0000-000000000016'
\set user2ID '79220000-0000-0000-0000-000000000017'
\set user3ID '79220000-0000-0000-0000-000000000018'
\set user4ID '79220000-0000-0000-0000-000000000019'

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
    'expire-stale-community',
    'Expire Stale Community',
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
        :'user1ID',
        'hash-1',
        'user1@example.com',
        true,
        'buyer-1'
    ),
    (
        :'user2ID',
        'hash-2',
        'user2@example.com',
        true,
        'buyer-2'
    ),
    (
        :'user3ID',
        'hash-3',
        'user3@example.com',
        true,
        'buyer-3'
    ),
    (
        :'user4ID',
        'hash-4',
        'user4@example.com',
        true,
        'buyer-4'
    );

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    payment_recipient
)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Expire Stale Group',
    'expire-stale-group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_expire_stale')
);

-- Events
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
    payment_currency_code,
    published,
    published_at
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Expire Stale Event',
    'expire-stale-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
), (
    :'otherEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Other Event',
    'other-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
);

-- Ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
)
values
    (
        :'ticketTypeID',
        :'eventID',
        1,
        10,
        'General admission'
    ),
    (
        :'otherTicketTypeID',
        :'otherEventID',
        1,
        10,
        'General admission'
    );

-- Price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'priceWindowID', 2500, :'ticketTypeID'),
    (:'otherPriceWindowID', 2500, :'otherTicketTypeID');

-- Discount code
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    true,
    500,
    1,
    true,
    'SAVE5',
    :'eventID',
    'fixed_amount',
    'Save 5'
);

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'stalePurchaseAID',
    2000,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'ticketTypeID',
    now() - interval '10 minutes',
    'pending',
    'General admission',
    :'user1ID'
), (
    :'stalePurchaseBID',
    2000,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'ticketTypeID',
    now() - interval '5 minutes',
    'pending',
    'General admission',
    :'user2ID'
), (
    :'activePurchaseID',
    2000,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'ticketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'user3ID'
), (
    :'otherEventPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'otherEventID',
    :'otherTicketTypeID',
    now() - interval '10 minutes',
    'pending',
    'General admission',
    :'user4ID'
);

-- Pending attendee rows with registration answers created during checkout
insert into event_attendee (event_id, user_id, status)
values
    (:'eventID', :'user1ID', 'registration-questions-pending'),
    (:'eventID', :'user2ID', 'registration-questions-pending'),
    (:'eventID', :'user3ID', 'registration-questions-pending'),
    (:'otherEventID', :'user4ID', 'registration-questions-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should expire stale pending holds for the selected event
select lives_ok(
    format($$select prepare_event_checkout_expire_stale_holds(%L::uuid)$$, :'eventID'),
    'Should expire stale pending holds for the selected event'
);

-- Should restore discount availability without touching active or other-event holds
select results_eq(
    format($$
        select
            (
                select count(*)::int
                from event_purchase
                where event_id = %L::uuid
                and status = 'expired'
            ),
            (
                select count(*)::int
                from event_purchase
                where event_id = %L::uuid
                and status = 'pending'
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = %L::uuid
            ),
            (
                select available::text
                from event_discount_code
                where event_discount_code_id = %L::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
            )
    $$, :'eventID', :'eventID', :'otherEventPurchaseID', :'discountCodeID', :'eventID', :'otherEventID'),
    $$ values (2::int, 1::int, 'pending'::text, '3'::text, 1::int, 1::int) $$,
    'Should restore discount availability and release only stale registration holds'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
