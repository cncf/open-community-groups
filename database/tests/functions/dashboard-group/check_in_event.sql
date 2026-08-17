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

-- Community containing the check-in event
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'A test community',
    'Test Community',
    'https://example.com/logo.png',
    'test-community'
);

-- Group category used by the check-in group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category used by the check-in events
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Organizer and attendee identities used by check-in scenarios
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'actorUserID', 'hash-1', 'actor@example.com', true, 'actor'),
    (:'attendeeUserID', 'hash-2', 'attendee@example.com', true, 'attendee'),
    (:'missingUserID', 'hash-3', 'missing@example.com', true, 'missing');

-- Group owning the check-in events
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Published event accepting organizer check-in at any time
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    published_at,
    slug,
    starts_at,
    timezone
) values (
    :'eventID',
    'An event for check-in tests',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Check-In Event',
    true,
    current_timestamp,
    'check-in-event',
    current_timestamp + interval '3 hours',
    'UTC'
);

-- Canceled event unavailable for check-in
insert into event (
    event_id,
    canceled,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    published_at,
    slug,
    starts_at,
    timezone
) values (
    :'canceledEventID',
    true,
    'A canceled event',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Canceled Event',
    false,
    null,
    'canceled-event',
    current_timestamp + interval '3 hours',
    'UTC'
);

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
            'actor',
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
    'event unavailable for check-in',
    'Should reject events that are unavailable for check-in'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
