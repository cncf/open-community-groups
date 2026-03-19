-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCanceled '00000000-0000-0000-0000-000000000043'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventDeleted '00000000-0000-0000-0000-000000000044'
\set eventFullNoWaitlist '00000000-0000-0000-0000-000000000047'
\set eventFullWaitlist '00000000-0000-0000-0000-000000000048'
\set eventInactiveGroup '00000000-0000-0000-0000-000000000045'
\set eventOK '00000000-0000-0000-0000-000000000041'
\set eventPast '00000000-0000-0000-0000-000000000046'
\set eventUnpublished '00000000-0000-0000-0000-000000000042'
\set groupID '00000000-0000-0000-0000-000000000021'
\set inactiveGroupID '00000000-0000-0000-0000-000000000022'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set user3ID '00000000-0000-0000-0000-000000000033'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'user1ID', 'h', 'u1@test.com', 'u1'),
    (:'user2ID', 'h', 'u2@test.com', 'u2'),
    (:'user3ID', 'h', 'u3@test.com', 'u3');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug, active, deleted)
values
    (:'groupID', :'communityID', :'categoryID', 'Active Group', 'active-group', true, false),
    (:'inactiveGroupID', :'communityID', :'categoryID', 'Inactive Group', 'inactive-group', false, false);

-- Events
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    canceled,
    deleted,
    starts_at,
    ends_at,
    capacity,
    waitlist_enabled
)
values
    (:'eventOK', 'OK', 'ok', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, null, false),
    (:'eventUnpublished', 'Unpub', 'unpub', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, false, null, null, null, false),
    (:'eventCanceled', 'Canceled', 'canceled', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, true, false, null, null, null, false),
    (:'eventDeleted', 'Deleted', 'deleted', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, true, null, null, null, false),
    (:'eventInactiveGroup', 'Inactive Group', 'inactive-group', 'd', 'UTC', :'eventCategoryID', 'in-person', :'inactiveGroupID', true, false, false, null, null, null, false),
    (:'eventPast', 'Past', 'past', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, current_timestamp - interval '2 hours', current_timestamp - interval '1 hour', null, false),
    (:'eventFullNoWaitlist', 'Full No Waitlist', 'full-no-waitlist', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, 2, false),
    (:'eventFullWaitlist', 'Full Waitlist', 'full-waitlist', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, 1, true);

-- Event attendees
insert into event_attendee (event_id, user_id)
values
    (:'eventFullNoWaitlist', :'user1ID'),
    (:'eventFullWaitlist', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should register a normal attendee when capacity allows
select is(
    attend_event(:'communityID'::uuid, :'eventOK'::uuid, :'user1ID'::uuid),
    'attendee',
    'Returns attendee when the user gets a confirmed seat'
);

-- Should create an attendee row after a successful RSVP
select ok(
    exists(
        select 1
        from event_attendee
        where event_id = :'eventOK'::uuid and user_id = :'user1ID'::uuid
    ),
    'Creates event_attendee row after confirmed RSVP'
);

-- Should allow attendance for a capacity-limited event with an open seat
select is(
    attend_event(:'communityID'::uuid, :'eventFullNoWaitlist'::uuid, :'user2ID'::uuid),
    'attendee',
    'Returns attendee when a capacity-limited event still has room'
);

-- Should reject RSVP when the event is full and waitlist is disabled
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventFullNoWaitlist', :'user3ID'
    ),
    'event has reached capacity',
    'Rejects new RSVP when the event is sold out and waitlist is disabled'
);

-- Should reject duplicate RSVP for a confirmed attendee
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventFullNoWaitlist', :'user1ID'
    ),
    'user is already attending this event',
    'Rejects duplicate RSVP for a confirmed attendee'
);

-- Should place the user on the waitlist when the event is full and waitlist is enabled
select is(
    attend_event(:'communityID'::uuid, :'eventFullWaitlist'::uuid, :'user2ID'::uuid),
    'waitlisted',
    'Returns waitlisted when the event is full and waitlist is enabled'
);

-- Should create a waitlist row after joining the waitlist
select ok(
    exists(
        select 1
        from event_waitlist
        where event_id = :'eventFullWaitlist'::uuid and user_id = :'user2ID'::uuid
    ),
    'Creates event_waitlist row after joining the waitlist'
);

-- Should reject duplicate waitlist joins
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventFullWaitlist', :'user2ID'
    ),
    'user is already on the waiting list for this event',
    'Rejects duplicate waitlist joins'
);

-- Should reject unpublished events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventUnpublished', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects unpublished events'
);

-- Should reject canceled events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventCanceled', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects canceled events'
);

-- Should reject deleted events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventDeleted', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects deleted events'
);

-- Should reject past events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventPast', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects past events'
);

-- Should reject events from inactive groups
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInactiveGroup', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects events from inactive groups'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
