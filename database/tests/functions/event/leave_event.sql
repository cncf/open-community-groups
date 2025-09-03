-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set inactiveGroupID '00000000-0000-0000-0000-000000000022'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set eventOK '00000000-0000-0000-0000-000000000041'
\set eventDeleted '00000000-0000-0000-0000-000000000044'
\set eventInactiveGroup '00000000-0000-0000-0000-000000000045'
\set eventUnpublished '00000000-0000-0000-0000-000000000046'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, host, title, description, header_logo_url, theme) values
(:'communityID', 'test-community', 'Test Community', 'test.community.org', 'Title', 'Desc', 'https://example.com/logo.png', '{}'::jsonb);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'General', 'general', :'communityID');

-- User
insert into "user" (user_id, username, email, community_id, auth_hash)
values 
    (:'user1ID', 'u1', 'u1@test.com', :'communityID', 'h'),
    (:'user2ID', 'u2', 'u2@test.com', :'communityID', 'h');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, active, deleted)
values
    (:'groupID', :'communityID', :'categoryID', 'Active Group', 'active-group', true, false),
    (:'inactiveGroupID', :'communityID', :'categoryID', 'Inactive Group', 'inactive-group', false, false);

-- Event
insert into event (event_id, name, slug, description, timezone, event_category_id, event_kind_id, group_id, published, canceled, deleted)
values
    (:'eventOK', 'OK', 'ok', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false),
    (:'eventDeleted', 'Deleted', 'deleted', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, true),
    (:'eventInactiveGroup', 'Inactive Group', 'inactive-group', 'd', 'UTC', :'eventCategoryID', 'in-person', :'inactiveGroupID', true, false, false),
    (:'eventUnpublished', 'Unpublished', 'unpublished', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, false);

-- Event Attendee
insert into event_attendee (event_id, user_id) values (:'eventOK', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: leave_event should succeed for attending user
select lives_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user1ID'
    ),
    'leave_event on attending user succeeds'
);

-- Test: leave_event should remove attendee record
select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventOK'::uuid and user_id = :'user1ID'::uuid
    ),
    'leave_event removes attendee record'
);

-- Test: leave_event when not attending should error
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user2ID'
    ),
    'P0001',
    'user is not attending this event',
    'leave_event not attending raises exception'
);

-- Test: leave_event in inactive group should error
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInactiveGroup', :'user1ID'
    ),
    'P0001',
    'event not found or inactive',
    'leave_event event in inactive group raises exception'
);

-- Test: leave_event deleted event should error
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventDeleted', :'user1ID'
    ),
    'P0001',
    'event not found or inactive',
    'leave_event deleted event raises exception'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
