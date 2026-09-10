-- Tests organizer-driven attendee check-in transitions and auditing.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '3a2a0000-0000-0000-0000-000000000001'
\set attendeeUserID '3a2a0000-0000-0000-0000-000000000002'
\set canceledEventID '3a2a0000-0000-0000-0000-000000000003'
\set communityID '3a2a0000-0000-0000-0000-000000000004'
\set eventCategoryID '3a2a0000-0000-0000-0000-000000000005'
\set eventID '3a2a0000-0000-0000-0000-000000000006'
\set groupCategoryID '3a2a0000-0000-0000-0000-000000000007'
\set groupID '3a2a0000-0000-0000-0000-000000000008'
\set missingUserID '3a2a0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');


-- Organizer and attendee identities used by check-in scenarios
select fx_user(:'actorUserID', jsonb_build_object('username', 'actor-check-in-event'));
select fx_user(:'attendeeUserID', jsonb_build_object('username', 'attendee-check-in-event'));
select fx_user(:'missingUserID', jsonb_build_object('username', 'missing'));

-- Published event accepting organizer check-in at any time
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '3 hours'
));

-- Canceled event unavailable for check-in
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'starts_at', current_timestamp + interval '3 hours'
));

-- Confirmed attendee eligible for organizer check-in
insert into event_attendee (event_id, user_id, status)
values (:'eventID', :'attendeeUserID', 'confirmed');

-- Confirmed attendee attached to the canceled event
insert into event_attendee (event_id, user_id, status)
values (:'canceledEventID', :'attendeeUserID', 'confirmed');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return true for the first check-in transition
select is(
    check_in_event(
        :'actorUserID'::uuid,
        :'communityID'::uuid,
        :'eventID'::uuid,
        :'attendeeUserID'::uuid
    ),
    true,
    'Should return true for the first check-in transition'
);

-- Should persist the checked-in state and timestamp
select ok(
    (
        select checked_in and checked_in_at is not null
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'attendeeUserID'::uuid
    ),
    'Should persist the checked-in state and timestamp'
);

-- Should create the scoped audit row
select results_eq(
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
    $$,
    format(
        $$ values (
            'event_attendee_checked_in',
            %L::uuid,
            'actor-check-in-event',
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
    'Should create the scoped audit row'
);

-- Capture the first transition timestamp for idempotency checks
select checked_in_at as "checkedInAt"
from event_attendee
where event_id = :'eventID'::uuid
and user_id = :'attendeeUserID'::uuid \gset firstCheckIn_

-- Should return false for a repeated check-in
select is(
    check_in_event(
        :'actorUserID'::uuid,
        :'communityID'::uuid,
        :'eventID'::uuid,
        :'attendeeUserID'::uuid
    ),
    false,
    'Should return false for a repeated check-in'
);

-- Should preserve the original check-in timestamp on repetition
select is(
    (
        select checked_in_at
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'attendeeUserID'::uuid
    ),
    :'firstCheckIn_checkedInAt'::timestamptz,
    'Should preserve the original check-in timestamp on repetition'
);

-- Should keep one audit row after a repeated check-in
select is(
    (select count(*)::int from audit_log),
    1,
    'Should keep one audit row after a repeated check-in'
);

-- Should reject users without confirmed attendance
select throws_ok(
    format(
        'select check_in_event(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'communityID',
        :'eventID',
        :'missingUserID'
    ),
    'OCG01',
    'attendance is not confirmed',
    'Should reject users without confirmed attendance'
);

-- Should reject events that are unavailable for check-in
select throws_ok(
    format(
        'select check_in_event(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'communityID',
        :'canceledEventID',
        :'attendeeUserID'
    ),
    'OCG01',
    'event unavailable for check-in',
    'Should reject events that are unavailable for check-in'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
