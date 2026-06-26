-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '0a050000-0000-0000-0000-000000000001'
\set groupCategoryID '0a050000-0000-0000-0000-000000000002'
\set groupID '0a050000-0000-0000-0000-000000000003'
\set nonExistentUserID '0a050000-0000-0000-0000-000000000004'
\set userBothTeamsID '0a050000-0000-0000-0000-000000000005'
\set userAllianceOnlyID '0a050000-0000-0000-0000-000000000006'
\set userGroupOnlyID '0a050000-0000-0000-0000-000000000007'
\set userNoTeamsID '0a050000-0000-0000-0000-000000000008'
\set userWithTeamsID '0a050000-0000-0000-0000-000000000009'

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
    'get-user-by-id-alliance',
    'Get User By ID Alliance',
    'Test alliance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Users
insert into "user" (
    user_id,
    name,
    auth_hash,
    bluesky_url,
    email,
    email_verified,
    github_url,
    password,
    provider,
    username
) values (
    :'userBothTeamsID',
    'Both Teams User',
    'test_hash_5',
    null,
    'both@example.com',
    true,
    null,
    null,
    null,
    'bothuser'
), (
    :'userAllianceOnlyID',
    'Alliance Only User',
    'test_hash_4',
    null,
    'allianceonly@example.com',
    true,
    null,
    null,
    null,
    'allianceonlyuser'
), (
    :'userGroupOnlyID',
    'Group Only User',
    'test_hash_3',
    null,
    'grouponly@example.com',
    true,
    null,
    null,
    null,
    'grouponlyuser'
), (
    :'userNoTeamsID',
    'No Groups User',
    'test_hash_2',
    null,
    'nogroups@example.com',
    true,
    null,
    null,
    null,
    'nogroupsuser'
), (
    :'userWithTeamsID',
    'Test User',
    'test_hash',
    'https://bsky.app/profile/testuser',
    'test@example.com',
    true,
    'https://github.com/testuser',
    'hashed_password_here',
    jsonb_build_object('github', jsonb_build_object('username', 'testuser-gh')),
    'testuser'
);

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    description,
    logo_url,
    slug,
    website_url
) values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Kubernetes Study Group',
    'Weekly Kubernetes study and discussion group',
    'https://example.com/logo.png',
    'kubernetes-study',
    'https://example.com'
);

-- Group team memberships
insert into group_team (group_id, user_id, role, accepted)
values
    (:'groupID', :'userBothTeamsID', 'admin', true),
    (:'groupID', :'userGroupOnlyID', 'admin', true),
    (:'groupID', :'userWithTeamsID', 'admin', true);

-- Alliance team memberships
insert into alliance_team (accepted, alliance_id, role, user_id)
values
    (true, :'allianceID', 'admin', :'userBothTeamsID'),
    (true, :'allianceID', 'admin', :'userAllianceOnlyID'),
    (true, :'allianceID', 'admin', :'userWithTeamsID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return user without password when include_password is false
select is(
    get_user_by_id(:'userWithTeamsID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash',
        'belongs_to_any_group_team', true,
        'belongs_to_alliance_team', true,
        'bluesky_url', 'https://bsky.app/profile/testuser',
        'email', 'test@example.com',
        'email_verified', true,
        'github_url', 'https://github.com/testuser',
        'has_password', true,
        'mentorship_businesses', false,
        'mentorship_individuals', false,
        'name', 'Test User',
        'optional_notifications_enabled', true,
        'platform_admin', false,
        'provider', jsonb_build_object('github', jsonb_build_object('username', 'testuser-gh')),
        'user_id', :'userWithTeamsID'::uuid,
        'username', 'testuser'
    ),
    'Should return user without password when include_password is false'
);

-- Should return user with password when include_password is true
select is(
    get_user_by_id(:'userWithTeamsID'::uuid, true)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash',
        'belongs_to_any_group_team', true,
        'belongs_to_alliance_team', true,
        'bluesky_url', 'https://bsky.app/profile/testuser',
        'email', 'test@example.com',
        'email_verified', true,
        'github_url', 'https://github.com/testuser',
        'has_password', true,
        'mentorship_businesses', false,
        'mentorship_individuals', false,
        'name', 'Test User',
        'optional_notifications_enabled', true,
        'password', 'hashed_password_here',
        'platform_admin', false,
        'provider', jsonb_build_object('github', jsonb_build_object('username', 'testuser-gh')),
        'user_id', :'userWithTeamsID'::uuid,
        'username', 'testuser'
    ),
    'Should return user with password when include_password is true'
);

-- Should return null when ID does not exist
select is(
    get_user_by_id(:'nonExistentUserID'::uuid, false)::jsonb,
    null::jsonb,
    'Should return null when ID does not exist'
);

-- Should return false team membership fields when user has no team memberships
select is(
    get_user_by_id(:'userNoTeamsID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash_2',
        'belongs_to_any_group_team', false,
        'belongs_to_alliance_team', false,
        'email', 'nogroups@example.com',
        'email_verified', true,
        'mentorship_businesses', false,
        'mentorship_individuals', false,
        'name', 'No Groups User',
        'optional_notifications_enabled', true,
        'platform_admin', false,
        'user_id', :'userNoTeamsID'::uuid,
        'username', 'nogroupsuser'
    ),
    'Should return false team membership fields when user has no team memberships'
);

-- Should return correct team flags when user is only in group team
select is(
    get_user_by_id(:'userGroupOnlyID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash_3',
        'belongs_to_any_group_team', true,
        'belongs_to_alliance_team', false,
        'email', 'grouponly@example.com',
        'email_verified', true,
        'mentorship_businesses', false,
        'mentorship_individuals', false,
        'name', 'Group Only User',
        'optional_notifications_enabled', true,
        'platform_admin', false,
        'user_id', :'userGroupOnlyID'::uuid,
        'username', 'grouponlyuser'
    ),
    'Should return correct team flags when user is only in group team'
);

-- Should return belongs_to_any_group_team true when user is in alliance team
select is(
    get_user_by_id(:'userAllianceOnlyID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash_4',
        'belongs_to_any_group_team', true,
        'belongs_to_alliance_team', true,
        'email', 'allianceonly@example.com',
        'email_verified', true,
        'mentorship_businesses', false,
        'mentorship_individuals', false,
        'name', 'Alliance Only User',
        'optional_notifications_enabled', true,
        'platform_admin', false,
        'user_id', :'userAllianceOnlyID'::uuid,
        'username', 'allianceonlyuser'
    ),
    'Should return belongs_to_any_group_team true when user is in alliance team'
);

-- Should return both team flags true when user is in both teams
select is(
    get_user_by_id(:'userBothTeamsID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash_5',
        'belongs_to_any_group_team', true,
        'belongs_to_alliance_team', true,
        'email', 'both@example.com',
        'email_verified', true,
        'mentorship_businesses', false,
        'mentorship_individuals', false,
        'name', 'Both Teams User',
        'optional_notifications_enabled', true,
        'platform_admin', false,
        'user_id', :'userBothTeamsID'::uuid,
        'username', 'bothuser'
    ),
    'Should return both team flags true when user is in both teams'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
