-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a220000-0000-0000-0000-000000000001'
\set groupCategoryID '3a220000-0000-0000-0000-000000000002'
\set groupID '3a220000-0000-0000-0000-000000000003'
\set missingGroupID '3a220000-0000-0000-0000-000000000004'
\set user1ID '3a220000-0000-0000-0000-000000000005'
\set user2ID '3a220000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'test-alliance',
    'Test Alliance',
    'A test alliance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Tech');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Test Group', 'test-group');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name,
    photo_url
) values (
    :'user1ID',
    gen_random_bytes(32),
    'alice@example.com',
    true,
    'alice',
    'Alice',
    'https://example.com/alice.png'
), (
    :'user2ID',
    gen_random_bytes(32),
    'bob@example.com',
    true,
    'bob',
    null,
    'https://example.com/bob.png'
);

-- Group members
insert into group_member (group_id, user_id, created_at)
values
    (:'groupID', :'user1ID', '2024-01-01 00:00:00+00'),
    (:'groupID', :'user2ID', '2024-01-02 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return members user ids ordered by user id
select is(
    list_group_members_ids(:'groupID'::uuid),
    array[:'user1ID'::uuid, :'user2ID'::uuid],
    'Should return members user ids ordered by user id'
);

-- Should return empty list for non-existing group
select is(
    list_group_members_ids(:'missingGroupID'::uuid),
    array[]::uuid[],
    'Should return empty list for non-existing group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
