-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventDeleted '00000000-0000-0000-0000-000000000044'
\set eventInactiveGroup '00000000-0000-0000-0000-000000000045'
\set eventOK '00000000-0000-0000-0000-000000000041'
\set eventPast '00000000-0000-0000-0000-000000000047'
\set eventUnpublished '00000000-0000-0000-0000-000000000046'
\set groupID '00000000-0000-0000-0000-000000000021'
\set inactiveGroupID '00000000-0000-0000-0000-000000000022'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- User
insert into "user" (user_id, auth_hash, email, username)
values
    (:'user1ID', 'h', 'u1@test.com', 'u1'),
    (:'user2ID', 'h', 'u2@test.com', 'u2');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, active, deleted)
values
    (:'groupID', :'communityID', :'categoryID', 'Active Group', 'active-group', true, false),
    (:'inactiveGroupID', :'communityID', :'categoryID', 'Inactive Group', 'inactive-group', false, false);

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
    ends_at
)
values
    (:'eventOK', 'OK', 'ok', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null),
    (:'eventDeleted', 'Deleted', 'deleted', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, true, null, null),
    (:'eventInactiveGroup', 'Inactive Group', 'inactive-group', 'd', 'UTC', :'eventCategoryID', 'in-person', :'inactiveGroupID', true, false, false, null, null),
    (:'eventUnpublished', 'Unpublished', 'unpublished', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, false, null, null),
    (:'eventPast', 'Past', 'past', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, current_timestamp - interval '2 hours', current_timestamp - interval '1 hour');

insert into event_attendee (event_id, user_id) values
    (:'eventOK', :'user1ID'),
    (:'eventPast', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed for attending user
select lives_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user1ID'
    ),
    'Should succeed for attending user'
);

-- Should remove attendee record
select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventOK'::uuid and user_id = :'user1ID'::uuid
    ),
    'Should remove attendee record'
);

-- Should error when user is not attending
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user2ID'
    ),
    'user is not attending this event',
    'Should error when user is not attending'
);

-- Should error for past event
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventPast', :'user1ID'
    ),
    'event not found or inactive',
    'Should error for past event'
);

-- Should error for event in inactive group
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInactiveGroup', :'user1ID'
    ),
    'event not found or inactive',
    'Should error for event in inactive group'
);

-- Should error for deleted event
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventDeleted', :'user1ID'
    ),
    'event not found or inactive',
    'Should error for deleted event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
