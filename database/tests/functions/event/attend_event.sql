-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCanceled '00000000-0000-0000-0000-000000000043'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventDeleted '00000000-0000-0000-0000-000000000044'
\set eventFull '00000000-0000-0000-0000-000000000047'
\set eventInactiveGroup '00000000-0000-0000-0000-000000000045'
\set eventOK '00000000-0000-0000-0000-000000000041'
\set eventPast '00000000-0000-0000-0000-000000000046'
\set eventUnpublished '00000000-0000-0000-0000-000000000042'
\set groupID '00000000-0000-0000-0000-000000000021'
\set inactiveGroupID '00000000-0000-0000-0000-000000000022'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, host, title, description, header_logo_url, theme) values
(:'communityID', 'test-community', 'Test Community', 'test.community.org', 'Title', 'Desc', 'https://example.com/logo.png', '{}'::jsonb);

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'General', 'general', :'communityID');

-- Users
insert into "user" (user_id, username, email, community_id, auth_hash)
values
    (:'user1ID', 'u1', 'u1@test.com', :'communityID', 'h'),
    (:'user2ID', 'u2', 'u2@test.com', :'communityID', 'h');

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
    capacity
)
values
    (:'eventOK', 'OK', 'ok', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, null),
    (:'eventUnpublished', 'Unpub', 'unpub', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, false, null, null, null),
    (:'eventCanceled', 'Canceled', 'canceled', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, true, false, null, null, null),
    (:'eventDeleted', 'Deleted', 'deleted', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, true, null, null, null),
    (:'eventInactiveGroup', 'Inactive Group', 'inactive-group', 'd', 'UTC', :'eventCategoryID', 'in-person', :'inactiveGroupID', true, false, false, null, null, null),
    (:'eventPast', 'Past', 'past', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, current_timestamp - interval '2 hours', current_timestamp - interval '1 hour', null),
    (:'eventFull', 'Full', 'full', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, 1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed for valid event
select lives_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user1ID'
    ),
    'User should be able to attend a valid event'
);

-- Should add user to event_attendee table
select ok(
    exists(
        select 1
        from event_attendee
        where event_id = :'eventOK'::uuid and user_id = :'user1ID'::uuid
    ),
    'User should be added to event_attendee table after attending'
);

-- Should let users join until capacity is reached
select lives_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventFull', :'user1ID'
    ),
    'User should be able to attend a capacity-limited event when space exists'
);

-- Should error when capacity limit is reached
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventFull', :'user2ID'
    ),
    'event has reached capacity',
    'Should reject attendance when event capacity is full'
);

-- Should error on duplicate attendance
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user1ID'
    ),
    'user is already attending this event',
    'Should not allow duplicate attendance'
);

-- Should error for unpublished event
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventUnpublished', :'user1ID'
    ),
    'event not found or inactive',
    'Should not allow attending unpublished event'
);

-- Should error for canceled event
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventCanceled', :'user1ID'
    ),
    'event not found or inactive',
    'Should not allow attending canceled event'
);

-- Should error for past event
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventPast', :'user1ID'
    ),
    'event not found or inactive',
    'Should not allow attending past event'
);

-- Should error for event in inactive group
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInactiveGroup', :'user1ID'
    ),
    'event not found or inactive',
    'Should not allow attending event from inactive group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
