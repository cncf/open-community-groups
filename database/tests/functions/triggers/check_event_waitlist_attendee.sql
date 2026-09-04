-- Tests event waitlist attendee constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ab040000-0000-0000-0000-000000000001'
\set event1ID 'ab040000-0000-0000-0000-000000000002'
\set event2ID 'ab040000-0000-0000-0000-000000000003'
\set eventCategoryID 'ab040000-0000-0000-0000-000000000004'
\set groupCategoryID 'ab040000-0000-0000-0000-000000000005'
\set groupID 'ab040000-0000-0000-0000-000000000006'
\set ticketType1ID 'ab040000-0000-0000-0000-00000000000a'
\set ticketType2ID 'ab040000-0000-0000-0000-00000000000b'
\set user1ID 'ab040000-0000-0000-0000-000000000007'
\set user2ID 'ab040000-0000-0000-0000-000000000008'
\set user3ID 'ab040000-0000-0000-0000-000000000009'
\set user4ID 'ab040000-0000-0000-0000-00000000000c'

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
select fx_event_ticket_type(:'ticketType1ID', :'event1ID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'ticketType2ID', :'event2ID', jsonb_build_object('seats_total', 1));

-- Existing attendees
insert into event_attendee (event_id, user_id)
values
    (:'event1ID', :'user1ID'),
    (:'event1ID', :'user4ID'),
    (:'event2ID', :'user1ID');

-- Existing waitlist entries
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values
    (:'event2ID', :'ticketType2ID', :'user2ID'),
    (:'event2ID', :'ticketType2ID', :'user4ID');

-- Existing active offers
insert into admission_offer (
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
)
values
    (
        :'event1ID',
        :'ticketType1ID',
        current_timestamp + interval '1 hour',
        'organizer_invitation',
        'pending',
        :'user3ID'
    ),
    (
        :'event2ID',
        :'ticketType2ID',
        current_timestamp + interval '1 hour',
        'organizer_invitation',
        'pending',
        :'user3ID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow waitlist inserts when the user is not already attending
select lives_ok(
    format(
        'insert into event_waitlist (event_id, event_ticket_type_id, user_id) values (%L, %L, %L)',
        :'event1ID',
        :'ticketType1ID',
        :'user2ID'
    ),
    'Should allow waitlist inserts when the user is not already attending'
);

-- Should reject waitlist inserts when the user is already attending
select throws_ok(
    format(
        'insert into event_waitlist (event_id, event_ticket_type_id, user_id) values (%L, %L, %L)',
        :'event1ID',
        :'ticketType1ID',
        :'user1ID'
    ),
    'OCG01',
    'user is already attending this event',
    'Should reject waitlist inserts when the user is already attending'
);

-- Should reject waitlist updates that move a user onto an attendee pair
select throws_ok(
    format(
        'update event_waitlist set user_id = %L where event_id = %L and user_id = %L',
        :'user1ID',
        :'event2ID',
        :'user2ID'
    ),
    'OCG01',
    'user is already attending this event',
    'Should reject waitlist updates that target an attendee pair'
);

-- Should validate the new event-user pair when a waitlist row changes events
select throws_ok(
    format(
        'update event_waitlist set event_id = %L, event_ticket_type_id = %L where event_id = %L and user_id = %L',
        :'event1ID',
        :'ticketType1ID',
        :'event2ID',
        :'user4ID'
    ),
    'OCG01',
    'user is already attending this event',
    'Should validate the new event-user pair when a waitlist row changes events'
);

-- Should reject waitlist writes that conflict with active offers
select throws_ok(
    format(
        'insert into event_waitlist (event_id, event_ticket_type_id, user_id) values (%L, %L, %L)',
        :'event1ID',
        :'ticketType1ID',
        :'user3ID'
    ),
    'OCG01',
    'user already has an active admission offer for this event',
    'Should reject waitlist inserts for active offer recipients'
);

select throws_ok(
    format(
        'update event_waitlist set user_id = %L where event_id = %L and user_id = %L',
        :'user3ID',
        :'event2ID',
        :'user2ID'
    ),
    'OCG01',
    'user already has an active admission offer for this event',
    'Should reject waitlist updates targeting active offer recipients'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
