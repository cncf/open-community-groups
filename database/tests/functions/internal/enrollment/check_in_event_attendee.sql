-- Tests the shared attendee check-in transition and its auditing.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID 'c1e20000-0000-0000-0000-000000000001'
\set alreadyCheckedInUserID 'c1e20000-0000-0000-0000-000000000002'
\set attendeeUserID 'c1e20000-0000-0000-0000-000000000003'
\set canceledAttendeeUserID 'c1e20000-0000-0000-0000-000000000004'
\set communityID 'c1e20000-0000-0000-0000-000000000005'
\set eventCategoryID 'c1e20000-0000-0000-0000-000000000006'
\set eventID 'c1e20000-0000-0000-0000-000000000007'
\set groupCategoryID 'c1e20000-0000-0000-0000-000000000008'
\set groupID 'c1e20000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the event
select fx_community(:'communityID');

-- Organizer performing the check-ins
select fx_user(:'actorUserID', jsonb_build_object('username', 'actor-check-in-event-attendee'));

-- Attendee checked in before the scenarios run
select fx_user(:'alreadyCheckedInUserID');

-- Attendee checked in by the first transition scenario
select fx_user(:'attendeeUserID');

-- Attendee whose attendance was canceled
select fx_user(:'canceledAttendeeUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose attendees are checked in
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Confirmed attendee already checked in at a known time
insert into event_attendee (event_id, user_id, checked_in, status, checked_in_at)
values (:'eventID', :'alreadyCheckedInUserID', true, 'confirmed', '2024-05-01 10:00:00+00');

-- Confirmed attendee not checked in yet
insert into event_attendee (event_id, user_id, status)
values (:'eventID', :'attendeeUserID', 'confirmed');

-- Attendee whose attendance is no longer confirmed
insert into event_attendee (event_id, user_id, status, attendance_canceled_at)
values (:'eventID', :'canceledAttendeeUserID', 'attendance-canceled', current_timestamp);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Run the first check-in transition and capture its result
select checked_in_at, transitioned
from check_in_event_attendee(
    :'actorUserID'::uuid,
    :'communityID'::uuid,
    :'groupID'::uuid,
    :'eventID'::uuid,
    :'attendeeUserID'::uuid
) \gset firstCheckIn_

-- Should report the first check-in transition
select is(
    :'firstCheckIn_transitioned'::boolean,
    true,
    'Should report the first check-in transition'
);

-- Should persist the returned check-in timestamp
select ok(
    (
        select ea.checked_in and ea.checked_in_at = :'firstCheckIn_checked_in_at'::timestamptz
        from event_attendee ea
        where ea.event_id = :'eventID'::uuid
        and ea.user_id = :'attendeeUserID'::uuid
    ),
    'Should persist the returned check-in timestamp'
);

-- Should audit the first check-in transition with the actor and scope
select results_eq(
    format(
        $$
            select
                action,
                actor_user_id,
                actor_username,
                community_id,
                event_id,
                group_id,
                resource_type,
                resource_id
            from audit_log
            where resource_id = %L::uuid
        $$,
        :'attendeeUserID'
    ),
    format(
        $$ values (
            'event_attendee_checked_in',
            %L::uuid,
            'actor-check-in-event-attendee',
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'user',
            %L::uuid
        ) $$,
        :'actorUserID',
        :'communityID',
        :'eventID',
        :'groupID',
        :'attendeeUserID'
    ),
    'Should audit the first check-in transition with the actor and scope'
);

-- Should return the original timestamp without a transition on repeated check-ins
select results_eq(
    format(
        $$
            select checked_in_at, transitioned
            from check_in_event_attendee(%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid)
        $$,
        :'actorUserID',
        :'communityID',
        :'groupID',
        :'eventID',
        :'alreadyCheckedInUserID'
    ),
    $$ values ('2024-05-01 10:00:00+00'::timestamptz, false) $$,
    'Should return the original timestamp without a transition on repeated check-ins'
);

-- Should not audit repeated check-ins
select is(
    (select count(*)::int from audit_log where resource_id = :'alreadyCheckedInUserID'::uuid),
    0,
    'Should not audit repeated check-ins'
);

-- Should reject users without confirmed attendance
select throws_ok(
    format(
        'select * from check_in_event_attendee(%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'communityID',
        :'groupID',
        :'eventID',
        :'canceledAttendeeUserID'
    ),
    'OCG01',
    'attendance is not confirmed',
    'Should reject users without confirmed attendance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
