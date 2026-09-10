-- Tests attendee waitlist and active offer trigger protections.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ab010000-0000-0000-0000-000000000001'
\set event1ID 'ab010000-0000-0000-0000-000000000002'
\set event2ID 'ab010000-0000-0000-0000-000000000003'
\set eventCategoryID 'ab010000-0000-0000-0000-000000000004'
\set groupCategoryID 'ab010000-0000-0000-0000-000000000005'
\set groupID 'ab010000-0000-0000-0000-000000000006'
\set user1ID 'ab010000-0000-0000-0000-000000000007'
\set user2ID 'ab010000-0000-0000-0000-000000000008'
\set user3ID 'ab010000-0000-0000-0000-000000000009'
\set user4ID 'ab010000-0000-0000-0000-00000000000a'
\set ticketType1ID 'ab010000-0000-0000-0000-00000000000b'
\set ticketType2ID 'ab010000-0000-0000-0000-00000000000c'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_user(:'user3ID');
select fx_user(:'user4ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
    'published', true,
    'waitlist_enabled', true
));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
    'published', true,
    'waitlist_enabled', true
));

-- Ticket tiers for the trigger-conflict fixtures
select fx_event_ticket_type(:'ticketType1ID', :'event1ID', jsonb_build_object(
    'seats_total', 1,
    'title', 'General admission'
));
select fx_event_ticket_type(:'ticketType2ID', :'event2ID', jsonb_build_object(
    'seats_total', 1,
    'title', 'General admission'
));

-- Existing waitlist entries
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values
    (:'event1ID', :'ticketType1ID', :'user1ID'),
    (:'event2ID', :'ticketType2ID', :'user1ID');

-- Existing attendee
insert into event_attendee (event_id, user_id)
values (:'event2ID', :'user2ID');

-- Existing active offers
insert into admission_offer (
    amount_minor,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
)
values
    (
        null,
        null,
        :'event1ID',
        :'ticketType1ID',
        current_timestamp + interval '1 hour',
        'organizer_invitation',
        'pending',
        null,
        :'user3ID'
    ),
    (
        null,
        null,
        :'event2ID',
        :'ticketType2ID',
        current_timestamp + interval '1 hour',
        'organizer_invitation',
        'pending',
        null,
        :'user3ID'
    ),
    (
        0,
        0,
        :'event1ID',
        :'ticketType1ID',
        current_timestamp + interval '1 hour',
        'organizer_invitation',
        'checkout_pending',
        'General admission',
        :'user4ID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow attendee inserts when the user is not on the waitlist
select lives_ok(
    format(
        'insert into event_attendee (event_id, user_id) values (%L, %L)',
        :'event1ID',
        :'user2ID'
    ),
    'Should allow attendee inserts when the user is not on the waitlist'
);

-- Should reject attendee inserts when the user is already on the waitlist
select throws_ok(
    format(
        'insert into event_attendee (event_id, user_id) values (%L, %L)',
        :'event1ID',
        :'user1ID'
    ),
    'OCG01',
    'user is already on the waiting list for this event',
    'Should reject attendee inserts when the user is already waitlisted'
);

-- Should reject attendee updates that move a user onto a waitlisted pair
select throws_ok(
    format(
        'update event_attendee set user_id = %L where event_id = %L and user_id = %L',
        :'user1ID',
        :'event2ID',
        :'user2ID'
    ),
    'OCG01',
    'user is already on the waiting list for this event',
    'Should reject attendee updates that target a waitlisted pair'
);

-- Should allow registration-question attendees with checkout-pending offers
select lives_ok(
    format(
        'insert into event_attendee (event_id, status, user_id) values (%L, %L, %L)',
        :'event1ID',
        'registration-questions-pending',
        :'user4ID'
    ),
    'Should allow registration-question attendees with checkout-pending offers'
);

-- Should reject attendee inserts for active offer recipients
select throws_ok(
    format(
        'insert into event_attendee (event_id, user_id) values (%L, %L)',
        :'event1ID',
        :'user3ID'
    ),
    'OCG01',
    'user already has an active admission offer for this event',
    'Should reject attendee inserts for active offer recipients'
);

-- Should reject attendee updates targeting active offer recipients
select throws_ok(
    format(
        'update event_attendee set user_id = %L where event_id = %L and user_id = %L',
        :'user3ID',
        :'event2ID',
        :'user2ID'
    ),
    'OCG01',
    'user already has an active admission offer for this event',
    'Should reject attendee updates targeting active offer recipients'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
