-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '72000000-0000-0000-0000-000000000001'
\set eventCategoryID '72000000-0000-0000-0000-000000000002'
\set eventID '72000000-0000-0000-0000-000000000003'
\set eventTicketTypeID '72000000-0000-0000-0000-000000000004'
\set groupCategoryID '72000000-0000-0000-0000-000000000005'
\set groupID '72000000-0000-0000-0000-000000000006'
\set freePurchaseID '72000000-0000-0000-0000-000000000007'
\set expiredPurchaseID '72000000-0000-0000-0000-000000000008'
\set paidPurchaseID '72000000-0000-0000-0000-000000000009'
\set completedPurchaseID '72000000-0000-0000-0000-000000000010'
\set priceWindowID '72000000-0000-0000-0000-000000000011'
\set user1ID '72000000-0000-0000-0000-000000000012'
\set user2ID '72000000-0000-0000-0000-000000000013'
\set user3ID '72000000-0000-0000-0000-000000000014'
\set user4ID '72000000-0000-0000-0000-000000000015'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'free-community', 'Free Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'user1ID', 'hash-1', 'user1@example.com', true, 'user-1'),
    (:'user2ID', 'hash-2', 'user2@example.com', true, 'user-2'),
    (:'user3ID', 'hash-3', 'user3@example.com', true, 'user-3'),
    (:'user4ID', 'hash-4', 'user4@example.com', true, 'user-4');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Free Group', 'free-group');

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
    'Free Event',
    'free-event',
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
    0,
    :'eventTicketTypeID'
);

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'freePurchaseID',
    0,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'user1ID'
), (
    :'expiredPurchaseID',
    0,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    now() - interval '10 minutes',
    'pending',
    'General admission',
    :'user2ID'
), (
    :'paidPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'user3ID'
), (
    :'completedPurchaseID',
    0,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    null,
    'completed',
    'General admission',
    :'user4ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should complete a pending free purchase
select is(
    complete_free_event_purchase(:'freePurchaseID'::uuid)::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'user_id', :'user1ID'::uuid
    ),
    'Should complete a pending free purchase'
);

-- Should persist the completed purchase fields and add the attendee
select results_eq(
    $$
        select
            (
                select completed_at is not null
                from event_purchase
                where event_purchase_id = '72000000-0000-0000-0000-000000000007'::uuid
            ),
            (
                select hold_expires_at is null
                from event_purchase
                where event_purchase_id = '72000000-0000-0000-0000-000000000007'::uuid
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = '72000000-0000-0000-0000-000000000007'::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = '72000000-0000-0000-0000-000000000003'::uuid
                and user_id = '72000000-0000-0000-0000-000000000012'::uuid
            )
    $$,
    $$ values (true, true, 'completed'::text, 1::int) $$,
    'Should persist the completed purchase fields and add the attendee'
);

-- Should reject expired purchase holds
select throws_ok(
    $$select complete_free_event_purchase('72000000-0000-0000-0000-000000000008'::uuid)$$,
    'purchase hold has expired',
    'Should reject expired purchase holds'
);

-- Should reject non-free purchases
select throws_ok(
    $$select complete_free_event_purchase('72000000-0000-0000-0000-000000000009'::uuid)$$,
    'only free purchases can be completed locally',
    'Should reject non-free purchases'
);

-- Should reject purchases that are no longer pending
select throws_ok(
    $$select complete_free_event_purchase('72000000-0000-0000-0000-000000000010'::uuid)$$,
    'purchase is no longer pending',
    'Should reject purchases that are no longer pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
