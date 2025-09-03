-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set inactiveGroupID '00000000-0000-0000-0000-000000000022'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set eventOK '00000000-0000-0000-0000-000000000041'
\set eventUnpublished '00000000-0000-0000-0000-000000000042'
\set eventCanceled '00000000-0000-0000-0000-000000000043'
\set eventDeleted '00000000-0000-0000-0000-000000000044'
\set eventInactiveGroup '00000000-0000-0000-0000-000000000045'

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
values (:'user1ID', 'u1', 'u1@test.com', :'communityID', 'h');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug, active, deleted)
values
    (:'groupID', :'communityID', :'categoryID', 'Active Group', 'active-group', true, false),
    (:'inactiveGroupID', :'communityID', :'categoryID', 'Inactive Group', 'inactive-group', false, false);

-- Events
insert into event (event_id, name, slug, description, timezone, event_category_id, event_kind_id, group_id, published, canceled, deleted)
values
    (:'eventOK', 'OK', 'ok', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false),
    (:'eventUnpublished', 'Unpub', 'unpub', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, false),
    (:'eventCanceled', 'Canceled', 'canceled', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, true, false),
    (:'eventDeleted', 'Deleted', 'deleted', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, true),
    (:'eventInactiveGroup', 'Inactive Group', 'inactive-group', 'd', 'UTC', :'eventCategoryID', 'in-person', :'inactiveGroupID', true, false, false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: attend_event should succeed for valid event
select lives_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user1ID'
    ),
    'User should be able to attend a valid event'
);

-- Test: attending should add user to event_attendee
select ok(
    exists(
        select 1
        from event_attendee
        where event_id = :'eventOK'::uuid and user_id = :'user1ID'::uuid
    ),
    'User should be added to event_attendee table after attending'
);

-- Test: attend_event duplicate should error
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user1ID'
    ),
    'P0001',
    'user is already attending this event',
    'Should not allow duplicate attendance'
);

-- Test: attend_event unpublished event should error
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventUnpublished', :'user1ID'
    ),
    'P0001',
    'event not found or inactive',
    'Should not allow attending unpublished event'
);

-- Test: attend_event canceled event should error
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventCanceled', :'user1ID'
    ),
    'P0001',
    'event not found or inactive',
    'Should not allow attending canceled event'
);

-- Test: attend_event in inactive group should error
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInactiveGroup', :'user1ID'
    ),
    'P0001',
    'event not found or inactive',
    'Should not allow attending event from inactive group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
