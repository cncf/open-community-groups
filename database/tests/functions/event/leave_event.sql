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
insert into event (event_id, name, slug, description, timezone, event_category_id, event_kind_id, group_id, published, canceled, deleted)
values
    (:'eventOK', 'OK', 'ok', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false),
    (:'eventDeleted', 'Deleted', 'deleted', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, true),
    (:'eventInactiveGroup', 'Inactive Group', 'inactive-group', 'd', 'UTC', :'eventCategoryID', 'in-person', :'inactiveGroupID', true, false, false),
    (:'eventUnpublished', 'Unpublished', 'unpublished', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, false);

-- Seed attendance for user1 in eventOK
insert into event_attendee (event_id, user_id) values (:'eventOK', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test successful leave
select lives_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user1ID'
    ),
    'User should be able to leave an event they attend'
);

-- Verify user was removed from event_attendee table
select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventOK'::uuid and user_id = :'user1ID'::uuid
    ),
    'User should be removed from event_attendee table after leaving'
);

-- Test leaving when not attending
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user2ID'
    ),
    'P0001',
    'user is not attending this event',
    'Should not allow user to leave an event they are not attending'
);

-- Test event in inactive group
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInactiveGroup', :'user1ID'
    ),
    'P0001',
    'event not found or inactive',
    'Should not allow leaving event from inactive group'
);

-- Test deleted event
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventDeleted', :'user1ID'
    ),
    'P0001',
    'event not found or inactive',
    'Should not allow leaving deleted event'
);

-- Test unpublished event
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventUnpublished', :'user1ID'
    ),
    'P0001',
    'event not found or inactive',
    'Should not allow leaving unpublished event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
