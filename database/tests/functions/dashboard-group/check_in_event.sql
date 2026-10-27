-- Tests organizer-driven attendee check-in within the selected group.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '3a2a0000-0000-0000-0000-000000000001'
\set attendeeUserID '3a2a0000-0000-0000-0000-000000000002'
\set canceledEventID '3a2a0000-0000-0000-0000-000000000003'
\set communityID '3a2a0000-0000-0000-0000-000000000004'
\set endedEventID '3a2a0000-0000-0000-0000-000000000010'
\set eventCategoryID '3a2a0000-0000-0000-0000-000000000005'
\set eventID '3a2a0000-0000-0000-0000-000000000006'
\set groupCategoryID '3a2a0000-0000-0000-0000-000000000007'
\set groupID '3a2a0000-0000-0000-0000-000000000008'
\set missingUserID '3a2a0000-0000-0000-0000-000000000009'
\set otherGroupEventID '3a2a0000-0000-0000-0000-000000000011'
\set otherGroupID '3a2a0000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the groups
select fx_community(:'communityID');

-- Organizer performing the check-ins
select fx_user(:'actorUserID', jsonb_build_object('username', 'actor-check-in-event'));

-- Attendee confirmed on every event
select fx_user(:'attendeeUserID', jsonb_build_object('username', 'attendee-check-in-event'));

-- User without attendance
select fx_user(:'missingUserID', jsonb_build_object('username', 'missing'));

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Selected group owning the checked-in events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Another group of the same community
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Published upcoming event that was canceled
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '3 hours'
));

-- Published event whose scanner window has closed
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 hours',
    'published', true,
    'published_at', current_timestamp - interval '1 day',
    'starts_at', current_timestamp - interval '3 hours'
));

-- Published upcoming event of the selected group
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '3 hours'
));

-- Published upcoming event of another group
select fx_event(:'otherGroupEventID', :'otherGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '3 hours'
));

-- Confirmed attendance on every event
insert into event_attendee (event_id, user_id, status)
values
    (:'canceledEventID', :'attendeeUserID', 'confirmed'),
    (:'endedEventID', :'attendeeUserID', 'confirmed'),
    (:'eventID', :'attendeeUserID', 'confirmed'),
    (:'otherGroupEventID', :'attendeeUserID', 'confirmed');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow manual check-in after the scanner window closes
select is(
    check_in_event(
        :'actorUserID'::uuid,
        :'communityID'::uuid,
        :'endedEventID'::uuid,
        :'groupID'::uuid,
        :'attendeeUserID'::uuid
    ),
    true,
    'Should allow manual check-in after the scanner window closes'
);

-- Should reject an event outside the selected group
select throws_ok(
    format(
        'select check_in_event(%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'communityID',
        :'otherGroupEventID',
        :'groupID',
        :'attendeeUserID'
    ),
    'OCG01',
    'event unavailable for check-in',
    'Should reject an event outside the selected group'
);

-- Should reject events that are unavailable for check-in
select throws_ok(
    format(
        'select check_in_event(%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'communityID',
        :'canceledEventID',
        :'groupID',
        :'attendeeUserID'
    ),
    'OCG01',
    'event unavailable for check-in',
    'Should reject events that are unavailable for check-in'
);

-- Should reject users without confirmed attendance
select throws_ok(
    format(
        'select check_in_event(%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'communityID',
        :'eventID',
        :'groupID',
        :'missingUserID'
    ),
    'OCG01',
    'attendance is not confirmed',
    'Should reject users without confirmed attendance'
);

-- Should return true for the first check-in transition
select is(
    check_in_event(
        :'actorUserID'::uuid,
        :'communityID'::uuid,
        :'eventID'::uuid,
        :'groupID'::uuid,
        :'attendeeUserID'::uuid
    ),
    true,
    'Should return true for the first check-in transition'
);

-- Should persist the checked-in state of the first transition
select ok(
    (
        select ea.checked_in and ea.checked_in_at is not null
        from event_attendee ea
        where ea.event_id = :'eventID'::uuid
        and ea.user_id = :'attendeeUserID'::uuid
    ),
    'Should persist the checked-in state of the first transition'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
