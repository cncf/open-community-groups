-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCanceledID '00000000-0000-0000-0000-000000000042'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventID '00000000-0000-0000-0000-000000000041'
\set eventStartedNoEndID '00000000-0000-0000-0000-000000000043'
\set groupID '00000000-0000-0000-0000-000000000031'
\set user1ID '00000000-0000-0000-0000-000000000051'
\set user2ID '00000000-0000-0000-0000-000000000052'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'communityID', 'cncf-sea', 'CNCF Seattle', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png'),
    (:'community2ID', 'cncf-ny', 'CNCF NY', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'Tech', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, logo_url, active)
values (:'groupID', 'Test Group', 'test-group', :'communityID', :'categoryID', 'https://example.com/group.png', true);

-- User
insert into "user" (user_id, auth_hash, email, username, name)
values
    (:'user1ID', 'h1', 'att1@example.com', 'att1', 'Att One'),
    (:'user2ID', 'h2', 'att2@example.com', 'att2', 'Att Two'),
    ('00000000-0000-0000-0000-000000000053', 'h3', 'att3@example.com', 'att3', 'Att Three');

-- Event
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
    starts_at
) values (
    :'eventID',
    'Event',
    'event',
    'desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true,
    false,
    null
), (
    :'eventCanceledID',
    'Canceled Event',
    'canceled-event',
    'desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    false,
    true,
    null
), (
    :'eventStartedNoEndID',
    'Started Event Without End',
    'started-event-without-end',
    'desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true,
    false,
    current_timestamp - interval '1 hour'
);

-- Event Attendee - user1 is checked in
insert into event_attendee (event_id, user_id, checked_in, checked_in_at) values (:'eventID', :'user1ID', true, current_timestamp);

-- Event Attendee - user2 is not checked in
insert into event_attendee (event_id, user_id, checked_in) values (:'eventID', :'user2ID', false);

-- Event Attendee - started event without end should still report attendee
insert into event_attendee (event_id, user_id, checked_in)
values (:'eventStartedNoEndID', :'user1ID', false);

-- Event Waitlist
insert into event_waitlist (event_id, user_id)
values
    (:'eventID', '00000000-0000-0000-0000-000000000053'),
    (:'eventCanceledID', '00000000-0000-0000-0000-000000000053');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return attendee status for checked-in attendee
select is(
    get_event_attendance(:'communityID'::uuid, :'eventID'::uuid, :'user1ID'::uuid)::jsonb,
    '{"is_checked_in":true,"status":"attendee"}'::jsonb,
    'Should return attendee status for a checked-in attendee'
);

-- Should return attendee status for attendee not checked in
select is(
    get_event_attendance(:'communityID'::uuid, :'eventID'::uuid, :'user2ID'::uuid)::jsonb,
    '{"is_checked_in":false,"status":"attendee"}'::jsonb,
    'Should return attendee status for an attendee not checked in'
);

-- Should return attendee status for a started event without an end time
select is(
    get_event_attendance(
        :'communityID'::uuid,
        :'eventStartedNoEndID'::uuid,
        :'user1ID'::uuid
    )::jsonb,
    '{"is_checked_in":false,"status":"attendee"}'::jsonb,
    'Should return attendee status for a started event without an end time'
);

-- Should return none when scoped by wrong community
select is(
    get_event_attendance(:'community2ID'::uuid, :'eventID'::uuid, :'user1ID'::uuid)::jsonb,
    '{"is_checked_in":false,"status":"none"}'::jsonb,
    'Should return none when scoped by wrong community'
);

-- Should return waitlisted status for waitlisted user
select is(
    get_event_attendance(
        :'communityID'::uuid,
        :'eventID'::uuid,
        '00000000-0000-0000-0000-000000000053'::uuid
    )::jsonb,
    '{"is_checked_in":false,"status":"waitlisted"}'::jsonb,
    'Should return waitlisted status for a waitlisted user'
);

-- Should return none for waitlisted users on canceled events
select is(
    get_event_attendance(
        :'communityID'::uuid,
        :'eventCanceledID'::uuid,
        '00000000-0000-0000-0000-000000000053'::uuid
    )::jsonb,
    '{"is_checked_in":false,"status":"none"}'::jsonb,
    'Should return none for waitlisted users on canceled events'
);

-- Should return none for non-attendee
select is(
    get_event_attendance(
        :'communityID'::uuid,
        :'eventID'::uuid,
        '00000000-0000-0000-0000-000000000054'::uuid
    )::jsonb,
    '{"is_checked_in":false,"status":"none"}'::jsonb,
    'Should return none for a non-attendee'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
