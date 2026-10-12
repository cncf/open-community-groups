-- Tests loading users by identifier with team membership flags.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityDeletedGroupsID '0a050000-0000-0000-0000-00000000000a'
\set communityID '0a050000-0000-0000-0000-000000000001'
\set communityNoGroupsID '0a050000-0000-0000-0000-00000000000b'
\set deletedGroupCategoryID '0a050000-0000-0000-0000-00000000000c'
\set deletedGroupID '0a050000-0000-0000-0000-00000000000d'
\set groupCategoryID '0a050000-0000-0000-0000-000000000002'
\set groupID '0a050000-0000-0000-0000-000000000003'
\set nonExistentUserID '0a050000-0000-0000-0000-000000000004'
\set userBothTeamsID '0a050000-0000-0000-0000-000000000005'
\set userCommunityDeletedGroupsID '0a050000-0000-0000-0000-00000000000e'
\set userCommunityNoGroupsID '0a050000-0000-0000-0000-00000000000f'
\set userCommunityOnlyID '0a050000-0000-0000-0000-000000000006'
\set userDeletedGroupOnlyID '0a050000-0000-0000-0000-000000000010'
\set userGroupOnlyID '0a050000-0000-0000-0000-000000000007'
\set userNoTeamsID '0a050000-0000-0000-0000-000000000008'
\set userWithTeamsID '0a050000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose only group has been deleted
select fx_community(:'communityDeletedGroupsID');

-- Community with groups used by team memberships
select fx_community(:'communityID');

-- Community without any groups
select fx_community(:'communityNoGroupsID');

-- User in both community and group teams
select fx_user(:'userBothTeamsID', jsonb_build_object(
    'auth_hash', 'test_hash_5',
    'email', 'both@example.com',
    'name', 'Both Teams User',
    'username', 'bothuser'
));

-- User in the team of the community with only deleted groups
select fx_user(:'userCommunityDeletedGroupsID', jsonb_build_object(
    'auth_hash', 'test_hash_7',
    'email', 'communitydeletedgroups@example.com',
    'name', 'Community Deleted Groups User',
    'username', 'communitydeletedgroupsuser'
));

-- User in the team of the community without groups
select fx_user(:'userCommunityNoGroupsID', jsonb_build_object(
    'auth_hash', 'test_hash_6',
    'email', 'communitynogroups@example.com',
    'name', 'Community No Groups User',
    'username', 'communitynogroupsuser'
));

-- User only in the team of the community with groups
select fx_user(:'userCommunityOnlyID', jsonb_build_object(
    'auth_hash', 'test_hash_4',
    'email', 'communityonly@example.com',
    'name', 'Community Only User',
    'username', 'communityonlyuser'
));

-- User only in the team of the deleted group
select fx_user(:'userDeletedGroupOnlyID', jsonb_build_object(
    'auth_hash', 'test_hash_8',
    'email', 'deletedgrouponly@example.com',
    'name', 'Deleted Group Only User',
    'username', 'deletedgrouponlyuser'
));

-- User only in the active group team
select fx_user(:'userGroupOnlyID', jsonb_build_object(
    'auth_hash', 'test_hash_3',
    'email', 'grouponly@example.com',
    'name', 'Group Only User',
    'username', 'grouponlyuser'
));

-- User without team memberships
select fx_user(:'userNoTeamsID', jsonb_build_object(
    'auth_hash', 'test_hash_2',
    'email', 'nogroups@example.com',
    'name', 'No Groups User',
    'username', 'nogroupsuser'
));

-- User with teams and optional profile fields
select fx_user(:'userWithTeamsID', jsonb_build_object(
    'auth_hash', 'test_hash',
    'bluesky_url', 'https://bsky.app/profile/testuser',
    'email', 'test@example.com',
    'github_url', 'https://github.com/testuser',
    'name', 'Test User',
    'password', 'hashed_password_here',
    'provider', jsonb_build_object('github', jsonb_build_object('username', 'testuser-gh')),
    'username', 'testuser'
));

-- Community team memberships
insert into community_team (accepted, community_id, role, user_id)
values
    (true, :'communityDeletedGroupsID', 'admin', :'userCommunityDeletedGroupsID'),
    (true, :'communityID', 'admin', :'userBothTeamsID'),
    (true, :'communityID', 'admin', :'userCommunityOnlyID'),
    (true, :'communityID', 'admin', :'userWithTeamsID'),
    (true, :'communityNoGroupsID', 'admin', :'userCommunityNoGroupsID');

-- Group category for the community with groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category for the community with only deleted groups
select fx_group_category(:'deletedGroupCategoryID', :'communityDeletedGroupsID');

-- Active group used by team memberships
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Deleted group that no longer grants group dashboard access
select fx_group(
    :'deletedGroupID',
    :'communityDeletedGroupsID',
    :'deletedGroupCategoryID',
    jsonb_build_object('active', false, 'deleted', true)
);

-- Group team memberships
insert into group_team (group_id, user_id, role, accepted)
values
    (:'deletedGroupID', :'userDeletedGroupOnlyID', 'admin', true),
    (:'groupID', :'userBothTeamsID', 'admin', true),
    (:'groupID', :'userGroupOnlyID', 'admin', true),
    (:'groupID', :'userWithTeamsID', 'admin', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return belongs_to_any_group_team false when community has no groups
select is(
    get_user_by_id(:'userCommunityNoGroupsID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash_6',
        'belongs_to_any_group_team', false,
        'belongs_to_community_team', true,
        'email', 'communitynogroups@example.com',
        'email_verified', true,
        'name', 'Community No Groups User',
        'user_id', :'userCommunityNoGroupsID'::uuid,
        'username', 'communitynogroupsuser'
    ),
    'Should return belongs_to_any_group_team false when community has no groups'
);

-- Should return belongs_to_any_group_team false when community only has deleted groups
select is(
    get_user_by_id(:'userCommunityDeletedGroupsID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash_7',
        'belongs_to_any_group_team', false,
        'belongs_to_community_team', true,
        'email', 'communitydeletedgroups@example.com',
        'email_verified', true,
        'name', 'Community Deleted Groups User',
        'user_id', :'userCommunityDeletedGroupsID'::uuid,
        'username', 'communitydeletedgroupsuser'
    ),
    'Should return belongs_to_any_group_team false when community only has deleted groups'
);

-- Should return belongs_to_any_group_team false when user only belongs to deleted group team
select is(
    get_user_by_id(:'userDeletedGroupOnlyID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash_8',
        'belongs_to_any_group_team', false,
        'belongs_to_community_team', false,
        'email', 'deletedgrouponly@example.com',
        'email_verified', true,
        'name', 'Deleted Group Only User',
        'user_id', :'userDeletedGroupOnlyID'::uuid,
        'username', 'deletedgrouponlyuser'
    ),
    'Should return belongs_to_any_group_team false when user only belongs to deleted group team'
);

-- Should return belongs_to_any_group_team true when user is in community team
select is(
    get_user_by_id(:'userCommunityOnlyID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash_4',
        'belongs_to_any_group_team', true,
        'belongs_to_community_team', true,
        'email', 'communityonly@example.com',
        'email_verified', true,
        'name', 'Community Only User',
        'user_id', :'userCommunityOnlyID'::uuid,
        'username', 'communityonlyuser'
    ),
    'Should return belongs_to_any_group_team true when user is in community team'
);

-- Should return both team flags true when user is in both teams
select is(
    get_user_by_id(:'userBothTeamsID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash_5',
        'belongs_to_any_group_team', true,
        'belongs_to_community_team', true,
        'email', 'both@example.com',
        'email_verified', true,
        'name', 'Both Teams User',
        'user_id', :'userBothTeamsID'::uuid,
        'username', 'bothuser'
    ),
    'Should return both team flags true when user is in both teams'
);

-- Should return correct team flags when user is only in group team
select is(
    get_user_by_id(:'userGroupOnlyID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash_3',
        'belongs_to_any_group_team', true,
        'belongs_to_community_team', false,
        'email', 'grouponly@example.com',
        'email_verified', true,
        'name', 'Group Only User',
        'user_id', :'userGroupOnlyID'::uuid,
        'username', 'grouponlyuser'
    ),
    'Should return correct team flags when user is only in group team'
);

-- Should return false team membership fields when user has no team memberships
select is(
    get_user_by_id(:'userNoTeamsID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash_2',
        'belongs_to_any_group_team', false,
        'belongs_to_community_team', false,
        'email', 'nogroups@example.com',
        'email_verified', true,
        'name', 'No Groups User',
        'user_id', :'userNoTeamsID'::uuid,
        'username', 'nogroupsuser'
    ),
    'Should return false team membership fields when user has no team memberships'
);

-- Should return null when ID does not exist
select is(
    get_user_by_id(:'nonExistentUserID'::uuid, false)::jsonb,
    null::jsonb,
    'Should return null when ID does not exist'
);

-- Should return user with password when include_password is true
select is(
    get_user_by_id(:'userWithTeamsID'::uuid, true)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash',
        'belongs_to_any_group_team', true,
        'belongs_to_community_team', true,
        'bluesky_url', 'https://bsky.app/profile/testuser',
        'email', 'test@example.com',
        'email_verified', true,
        'github_url', 'https://github.com/testuser',
        'has_password', true,
        'name', 'Test User',
        'password', 'hashed_password_here',
        'provider', jsonb_build_object('github', jsonb_build_object('username', 'testuser-gh')),
        'user_id', :'userWithTeamsID'::uuid,
        'username', 'testuser'
    ),
    'Should return user with password when include_password is true'
);

-- Should return user without password when include_password is false
select is(
    get_user_by_id(:'userWithTeamsID'::uuid, false)::jsonb,
    jsonb_build_object(
        'auth_hash', 'test_hash',
        'belongs_to_any_group_team', true,
        'belongs_to_community_team', true,
        'bluesky_url', 'https://bsky.app/profile/testuser',
        'email', 'test@example.com',
        'email_verified', true,
        'github_url', 'https://github.com/testuser',
        'has_password', true,
        'name', 'Test User',
        'provider', jsonb_build_object('github', jsonb_build_object('username', 'testuser-gh')),
        'user_id', :'userWithTeamsID'::uuid,
        'username', 'testuser'
    ),
    'Should return user without password when include_password is false'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
