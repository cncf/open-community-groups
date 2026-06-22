-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(22);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set checkInWindowEventID '5e030000-0000-0000-0000-000000000001'
\set allianceID '5e030000-0000-0000-0000-000000000002'
\set eventCategoryID '5e030000-0000-0000-0000-000000000003'
\set futureEventID '5e030000-0000-0000-0000-000000000004'
\set groupCategoryID '5e030000-0000-0000-0000-000000000005'
\set groupID '5e030000-0000-0000-0000-000000000006'
\set multiDayEventID '5e030000-0000-0000-0000-000000000007'
\set noStartTimeEventID '5e030000-0000-0000-0000-000000000008'
\set pastEventID '5e030000-0000-0000-0000-000000000009'
\set sameDayWithEndsAtEventID '5e030000-0000-0000-0000-00000000000a'
\set unknownEventID '5e030000-0000-0000-0000-00000000000b'
\set userID '5e030000-0000-0000-0000-00000000000c'
\set userID2 '5e030000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'test-alliance',
    'Test Alliance',
    'A test alliance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'userID', 'user-hash', 'user@test.local', true, 'user'),
    (:'userID2', 'user-2-hash', 'user2@test.local', true, 'user2');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'A test group'
);

-- Event 1: Future event (outside check-in window)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    published,
    published_at
) values (
    :'futureEventID',
    :'groupID',
    'Future Event',
    'future-event',
    'A future event',
    'UTC',
    :'eventCategoryID',
    'in-person',
    now() + interval '3 hours',
    true,
    now()
);

-- Event 2: Event within check-in window
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    published,
    published_at
) values (
    :'checkInWindowEventID',
    :'groupID',
    'Check-In Window Event',
    'check-in-window-event',
    'An event within check-in window',
    'UTC',
    :'eventCategoryID',
    'in-person',
    now() + interval '1 hour',
    true,
    now()
);

-- Event 3: Past event (outside check-in window)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published,
    published_at
) values (
    :'pastEventID',
    :'groupID',
    'Past Event',
    'past-event',
    'A past event',
    'UTC',
    :'eventCategoryID',
    'in-person',
    now() - interval '2 days',
    now() - interval '1 day',
    true,
    now() - interval '3 days'
);

-- Event 4: Multi-day event still ongoing
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published,
    published_at
) values (
    :'multiDayEventID',
    :'groupID',
    'Multi-Day Event',
    'multi-day-event',
    'A multi-day event spanning multiple days',
    'UTC',
    :'eventCategoryID',
    'in-person',
    now() - interval '1 day',
    now() + interval '1 day',
    true,
    now()
);

-- Event 5: Same day event with ends_at
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published,
    published_at
) values (
    :'sameDayWithEndsAtEventID',
    :'groupID',
    'Same Day Event',
    'same-day-event',
    'An event that starts and ends on the same day',
    'UTC',
    :'eventCategoryID',
    'in-person',
    now() - interval '1 hour',
    now() + interval '1 hour',
    true,
    now()
);

-- Event 5: Event without start time
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    published_at
) values (
    :'noStartTimeEventID',
    :'groupID',
    'No Start Time Event',
    'no-start-time-event',
    'An event without start time',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    now()
);

-- Attendees registration
insert into event_attendee (event_id, user_id, status) values
    (:'futureEventID'::uuid, :'userID'::uuid, 'confirmed'),
    (:'futureEventID'::uuid, :'userID2'::uuid, 'confirmed'),
    (:'checkInWindowEventID'::uuid, :'userID'::uuid, 'confirmed'),
    (:'checkInWindowEventID'::uuid, :'userID2'::uuid, 'invitation-pending'),
    (:'noStartTimeEventID'::uuid, :'userID'::uuid, 'confirmed'),
    (:'pastEventID'::uuid, :'userID'::uuid, 'confirmed'),
    (:'multiDayEventID'::uuid, :'userID'::uuid, 'confirmed'),
    (:'sameDayWithEndsAtEventID'::uuid, :'userID'::uuid, 'confirmed');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when within the allowed window
select lives_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,false)',
        :'allianceID', :'checkInWindowEventID', :'userID'
    ),
    'Should succeed within allowed window'
);

-- Should set the checked_in flag
select is(
    (
        select checked_in
        from event_attendee
        where event_id = :'checkInWindowEventID'::uuid and user_id = :'userID'::uuid
    ),
    true,
    'Should mark attendee as checked in'
);

-- Should set checked_in_at to a recent timestamp
select ok(
    (
        select checked_in_at >= now() - interval '10 seconds'
        and checked_in_at <= now() + interval '10 seconds'
        from event_attendee
        where event_id = :'checkInWindowEventID'::uuid and user_id = :'userID'::uuid
    ),
    'Should set checked_in_at to current time'
);

-- Should error when user has only a pending organizer-created invitation
select throws_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,false)',
        :'allianceID', :'checkInWindowEventID', :'userID2'
    ),
    'user is not registered for this event',
    'Should require confirmed attendee record'
);

-- Should leave pending invitation rows unchecked
select is(
    (
        select checked_in
        from event_attendee
        where event_id = :'checkInWindowEventID'::uuid
        and user_id = :'userID2'::uuid
    ),
    false,
    'Should leave pending invitation rows unchecked'
);

-- Should error if window has not opened yet
select throws_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,false)',
        :'allianceID', :'futureEventID', :'userID'
    ),
    'check-in window closed',
    'Should error before start window'
);

-- Should error if window already closed
select throws_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,false)',
        :'allianceID', :'pastEventID', :'userID'
    ),
    'check-in window closed',
    'Should error after allowed time'
);

-- Should error when event not found
select throws_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,false)',
        :'allianceID', :'unknownEventID', :'userID'
    ),
    'event not found or inactive',
    'Should throw error when event does not exist'
);

-- Should allow check-in to multi-day event within window
select lives_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,false)',
        :'allianceID', :'multiDayEventID', :'userID'
    ),
    'Should allow check-in for ongoing multi-day event'
);
select is(
    (select checked_in from event_attendee where event_id = :'multiDayEventID' and user_id = :'userID'),
    true,
    'Should mark attendee checked in for ongoing multi-day event'
);

-- Should allow check-in to same-day event with ends_at within window
select lives_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,false)',
        :'allianceID', :'sameDayWithEndsAtEventID', :'userID'
    ),
    'Should allow check-in for same-day event with ends_at'
);
select is(
    (select checked_in from event_attendee where event_id = :'sameDayWithEndsAtEventID' and user_id = :'userID'),
    true,
    'Should mark attendee checked in for same-day event with ends_at'
);

-- Should error when event has no start time
select throws_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,false)',
        :'allianceID', :'noStartTimeEventID', :'userID'
    ),
    'event has no start time',
    'Should throw error when event has no start time'
);

-- Should be idempotent - can call multiple times
select lives_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,false)',
        :'allianceID', :'checkInWindowEventID', :'userID'
    ),
    'Should allow repeated check_in_event calls'
);
select is(
    (select count(*)::int from event_attendee where event_id = :'checkInWindowEventID' and user_id = :'userID' and checked_in = true),
    1,
    'Should keep only one checked-in attendee record'
);

-- Should not update checked_in_at on subsequent check-ins
select checked_in_at as "checkedInAt"
from event_attendee
where event_id = :'checkInWindowEventID'::uuid and user_id = :'userID'::uuid \gset previousCheckIn_
select lives_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,false)',
        :'allianceID', :'checkInWindowEventID', :'userID'
    ),
    'Should allow subsequent check-ins without error'
);
select is(
    (
        select checked_in_at
        from event_attendee
        where event_id = :'checkInWindowEventID'::uuid and user_id = :'userID'::uuid
    ),
    :'previousCheckIn_checkedInAt'::timestamptz,
    'Should keep original checked_in_at on subsequent check-ins'
);

-- Should succeed with bypass_window for future event (outside check-in window)
select lives_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,true)',
        :'allianceID', :'futureEventID', :'userID'
    ),
    'Should allow check-in with bypass_window for future event'
);
select is(
    (select checked_in from event_attendee where event_id = :'futureEventID' and user_id = :'userID'),
    true,
    'Should mark attendee checked in with bypass_window for future event'
);

-- Should succeed with bypass_window for event without start time
select lives_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,true)',
        :'allianceID', :'noStartTimeEventID', :'userID'
    ),
    'Should allow check-in with bypass_window for event without start time'
);
select is(
    (select checked_in from event_attendee where event_id = :'noStartTimeEventID' and user_id = :'userID'),
    true,
    'Should mark attendee checked in with bypass_window for event without start time'
);

-- Should still require user to be registered even with bypass_window
select throws_ok(
    format(
        'select check_in_event(%L::uuid,%L::uuid,%L::uuid,true)',
        :'allianceID', :'checkInWindowEventID', :'userID2'
    ),
    'user is not registered for this event',
    'Should still require user registration even with bypass_window'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
