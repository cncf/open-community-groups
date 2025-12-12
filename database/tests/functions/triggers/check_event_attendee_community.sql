-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set eventID '00000000-0000-0000-0000-000000000101'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000051'
\set user1ID '00000000-0000-0000-0000-000000000020'
\set user2ID '00000000-0000-0000-0000-000000000021'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community 1
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'community1ID',
    'community-1',
    'Community 1',
    'community1.example.org',
    'Community 1',
    'Test community 1',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Community 2
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'community2ID',
    'community-2',
    'Community 2',
    'community2.example.org',
    'Community 2',
    'Test community 2',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Users
insert into "user" (user_id, community_id, email, username, auth_hash, name) values
    (:'user1ID', :'community1ID', 'user1@example.com', 'user1', 'hash1', 'User One'),
    (:'user2ID', :'community2ID', 'user2@example.com', 'user2', 'hash2', 'User Two');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'categoryID', 'Conference', 'conference', :'community1ID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'community1ID');

-- Group (belongs to community 1)
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'community1ID',
    'Test Group',
    'test-group',
    'A test group',
    :'groupCategoryID'
);

-- Event (belongs to group in community 1)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values (
    :'eventID',
    :'groupID',
    'Test Event',
    'test-event',
    'A test event',
    'UTC',
    :'categoryID',
    'in-person'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when attendee is from same community as event
select lives_ok(
    format('insert into event_attendee (event_id, user_id) values (%L, %L)', :'eventID', :'user1ID'),
    'Should succeed when attendee is from same community as event'
);

-- Should fail when attendee is from different community
select throws_ok(
    format('insert into event_attendee (event_id, user_id) values (%L, %L)', :'eventID', :'user2ID'),
    'user not found in community',
    'Should fail when attendee is from different community'
);

-- Should fail when updating event_attendee to user from different community
select throws_ok(
    format('update event_attendee set user_id = %L where event_id = %L', :'user2ID', :'eventID'),
    'user not found in community',
    'Should fail when updating event_attendee to user from different community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
