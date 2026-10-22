-- Tests loading users by identifier with team membership flags.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

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
\set userPendingCommunityTeamID '0a050000-0000-0000-0000-000000000011'
\set userPendingGroupTeamID '0a050000-0000-0000-0000-000000000012'
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
select fx_user(:'userBothTeamsID');

-- User in the team of the community with only deleted groups
select fx_user(:'userCommunityDeletedGroupsID');

-- User in the team of the community without groups
select fx_user(:'userCommunityNoGroupsID');

-- User only in the team of the community with groups
select fx_user(:'userCommunityOnlyID');

-- User only in the team of the deleted group
select fx_user(:'userDeletedGroupOnlyID');

-- User only in the active group team
select fx_user(:'userGroupOnlyID');

-- User without team memberships
select fx_user(:'userNoTeamsID');

-- User with only a pending invitation to the team of the community with groups
select fx_user(:'userPendingCommunityTeamID');

-- User with only a pending invitation to the active group team
select fx_user(:'userPendingGroupTeamID');

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

-- Community team memberships, accepted and pending
insert into community_team (accepted, community_id, role, user_id)
values
    (true, :'communityDeletedGroupsID', 'admin', :'userCommunityDeletedGroupsID'),
    (true, :'communityID', 'admin', :'userBothTeamsID'),
    (true, :'communityID', 'admin', :'userCommunityOnlyID'),
    (false, :'communityID', 'admin', :'userPendingCommunityTeamID'),
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

-- Group team memberships, accepted and pending
insert into group_team (accepted, group_id, role, user_id)
values
    (true, :'deletedGroupID', 'admin', :'userDeletedGroupOnlyID'),
    (true, :'groupID', 'admin', :'userBothTeamsID'),
    (true, :'groupID', 'admin', :'userGroupOnlyID'),
    (false, :'groupID', 'admin', :'userPendingGroupTeamID'),
    (true, :'groupID', 'admin', :'userWithTeamsID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should compute the team membership flags for every membership shape
select results_eq(
    $$
        select
            user_id,
            (get_user_by_id(user_id, false)::jsonb->>'belongs_to_any_group_team')::boolean,
            (get_user_by_id(user_id, false)::jsonb->>'belongs_to_community_team')::boolean
        from "user"
        where user_id::text like '0a050000-%'
        order by user_id
    $$,
    format(
        $$
            values
                -- Accepted in both the community team and the group team
                (%L::uuid, true, true),
                -- Accepted in the team of a community with an active group
                (%L::uuid, true, true),
                -- Accepted in the active group team only
                (%L::uuid, true, false),
                -- No team memberships
                (%L::uuid, false, false),
                -- Accepted in both teams, with optional profile fields
                (%L::uuid, true, true),
                -- Accepted in the team of a community whose only group is deleted
                (%L::uuid, false, true),
                -- Accepted in the team of a community without groups
                (%L::uuid, false, true),
                -- Accepted in the deleted group team only
                (%L::uuid, false, false),
                -- Pending in the team of a community with an active group
                (%L::uuid, false, false),
                -- Pending in the active group team
                (%L::uuid, false, false)
        $$,
        :'userBothTeamsID',
        :'userCommunityOnlyID',
        :'userGroupOnlyID',
        :'userNoTeamsID',
        :'userWithTeamsID',
        :'userCommunityDeletedGroupsID',
        :'userCommunityNoGroupsID',
        :'userDeletedGroupOnlyID',
        :'userPendingCommunityTeamID',
        :'userPendingGroupTeamID'
    ),
    'Should compute the team membership flags for every membership shape'
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
