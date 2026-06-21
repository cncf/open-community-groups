-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '72000000-0000-0000-0000-000000000001'
\set eventCategoryID '72000000-0000-0000-0000-000000000002'
\set eventID '72000000-0000-0000-0000-000000000003'
\set eventInactiveID '72000000-0000-0000-0000-000000000016'
\set eventTicketTypeID '72000000-0000-0000-0000-000000000004'
\set eventInactiveTicketTypeID '72000000-0000-0000-0000-000000000017'
\set groupCategoryID '72000000-0000-0000-0000-000000000005'
\set groupID '72000000-0000-0000-0000-000000000006'
\set freePurchaseID '72000000-0000-0000-0000-000000000007'
\set expiredPurchaseID '72000000-0000-0000-0000-000000000008'
\set inactivePurchaseID '72000000-0000-0000-0000-000000000018'
\set paidPurchaseID '72000000-0000-0000-0000-000000000009'
\set completedPurchaseID '72000000-0000-0000-0000-000000000010'
\set priceWindowID '72000000-0000-0000-0000-000000000011'
\set user1ID '72000000-0000-0000-0000-000000000012'
\set user2ID '72000000-0000-0000-0000-000000000013'
\set user3ID '72000000-0000-0000-0000-000000000014'
\set user4ID '72000000-0000-0000-0000-000000000015'
\set user5ID '72000000-0000-0000-0000-000000000019'
\set invitedPurchaseID '72000000-0000-0000-0000-000000000020'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'allianceID', 'free-alliance', 'Free Alliance', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Tech');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'user1ID', 'hash-1', 'user1@example.com', true, 'user-1'),
    (:'user2ID', 'hash-2', 'user2@example.com', true, 'user-2'),
    (:'user3ID', 'hash-3', 'user3@example.com', true, 'user-3'),
    (:'user4ID', 'hash-4', 'user4@example.com', true, 'user-4'),
    (:'user5ID', 'hash-5', 'user5@example.com', true, 'user-5');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Free Group', 'free-group');

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
    published_at,
    registration_questions
) values (
    -- Event with pending registration answers created during checkout
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
    now(),
    '[{"id": "72000000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb
), (
    :'eventInactiveID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Inactive Free Event',
    'inactive-free-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    true,
    now(),
    '[]'::jsonb
);

-- Ticket type
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values
    (:'eventTicketTypeID', :'eventID', 1, 10, 'General admission'),
    (:'eventInactiveTicketTypeID', :'eventInactiveID', 1, 10, 'General admission');

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
    :'inactivePurchaseID',
    0,
    'USD',
    :'eventInactiveID',
    :'eventInactiveTicketTypeID',
    now() + interval '10 minutes',
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
), (
    :'invitedPurchaseID',
    0,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'user5ID'
);

-- Pending attendee row with registration answers created during checkout
insert into event_attendee (event_id, user_id, registration_answers, status)
values (
    :'eventID',
    :'user1ID',
    '{"answers": [{"question_id": "72000000-0000-0000-0000-000000000101", "value": "Free checkout answer"}]}'::jsonb,
    'registration-questions-pending'
);

-- Attendee with a pending invitation that checkout cannot confirm
insert into event_attendee (event_id, user_id, manually_invited, status)
values (:'eventID', :'user5ID', true, 'invitation-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should complete a pending free purchase
select is(
    complete_free_event_purchase(:'freePurchaseID'::uuid)::jsonb,
    jsonb_build_object(
        'alliance_id', :'allianceID'::uuid,
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
            ),
            (
                select manually_invited
                from event_attendee
                where event_id = '72000000-0000-0000-0000-000000000003'::uuid
                and user_id = '72000000-0000-0000-0000-000000000012'::uuid
            ),
            (
                select status
                from event_attendee
                where event_id = '72000000-0000-0000-0000-000000000003'::uuid
                and user_id = '72000000-0000-0000-0000-000000000012'::uuid
            ),
            (
                select registration_answers
                from event_attendee
                where event_id = '72000000-0000-0000-0000-000000000003'::uuid
                and user_id = '72000000-0000-0000-0000-000000000012'::uuid
            )
    $$,
    $$
        values (
            true,
            true,
            'completed'::text,
            1::int,
            false,
            'confirmed'::text,
            '{"answers": [{"question_id": "72000000-0000-0000-0000-000000000101", "value": "Free checkout answer"}]}'::jsonb
        )
    $$,
    'Should persist the completed purchase fields and confirm a non-manually invited attendee'
);

-- Should reject expired purchase holds
select throws_ok(
    $$select complete_free_event_purchase('72000000-0000-0000-0000-000000000008'::uuid)$$,
    'purchase hold has expired',
    'Should reject expired purchase holds'
);

-- Should reject free purchases when the event becomes inactive
update event
set published = false
where event_id = :'eventInactiveID'::uuid;

select throws_ok(
    $$select complete_free_event_purchase('72000000-0000-0000-0000-000000000018'::uuid)$$,
    'event not found or inactive',
    'Should reject free purchases when the event becomes inactive'
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

-- Should reject purchases whose attendee row cannot be confirmed
select throws_ok(
    $$select complete_free_event_purchase('72000000-0000-0000-0000-000000000020'::uuid)$$,
    'attendee cannot be confirmed for this event',
    'Should reject purchases whose attendee row cannot be confirmed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
