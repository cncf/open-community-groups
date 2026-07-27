-- Tests listing groups where a user is a member or accepted team member.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a0d0000-0000-0000-0000-000000000001'
\set deletedGroupID '4a0d0000-0000-0000-0000-000000000002'
\set emptyUserID '4a0d0000-0000-0000-0000-000000000003'
\set groupCategoryID '4a0d0000-0000-0000-0000-000000000004'
\set inactiveCommunityCategoryID '4a0d0000-0000-0000-0000-000000000011'
\set inactiveCommunityGroupID '4a0d0000-0000-0000-0000-000000000012'
\set inactiveCommunityID '4a0d0000-0000-0000-0000-000000000013'
\set inactiveGroupID '4a0d0000-0000-0000-0000-000000000005'
\set memberGroupID '4a0d0000-0000-0000-0000-000000000006'
\set memberTeamGroupID '4a0d0000-0000-0000-0000-000000000007'
\set pendingTeamGroupID '4a0d0000-0000-0000-0000-000000000008'
\set teamGroupID '4a0d0000-0000-0000-0000-000000000009'
\set userID '4a0d0000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the group relationships
insert into community (
    community_id,
    active,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    true,
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'Community for user group listing tests',
    'User Groups Community',
    'https://example.com/logo.png',
    'user-groups-community'
);

-- Inactive community containing an otherwise visible group
insert into community (
    community_id,
    active,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'inactiveCommunityID',
    false,
    'https://example.com/inactive-banner-mobile.png',
    'https://example.com/inactive-banner.png',
    'Inactive community for user group listing tests',
    'Inactive User Groups Community',
    'https://example.com/inactive-logo.png',
    'inactive-user-groups-community'
);

-- Category shared by the group fixtures
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    :'groupCategoryID',
    :'communityID',
    'Technology'
);

-- Category belonging to the inactive community
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    :'inactiveCommunityCategoryID',
    :'inactiveCommunityID',
    'Inactive Technology'
);

-- Users with populated and empty group listings
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username
) values (
    :'emptyUserID',
    'hash-empty',
    'groups-empty@example.com',
    true,
    'groups-empty'
), (
    :'userID',
    'hash-user',
    'groups-user@example.com',
    true,
    'groups-user'
);

-- Active, hidden, and pending group relationship fixtures
insert into "group" (
    group_id,
    active,
    community_id,
    deleted,
    group_category_id,
    name,
    slug
) values (
    :'memberGroupID',
    true,
    :'communityID',
    false,
    :'groupCategoryID',
    'Alpha Group',
    'alpha-group'
), (
    :'memberTeamGroupID',
    true,
    :'communityID',
    false,
    :'groupCategoryID',
    'Beta Group',
    'beta-group'
), (
    :'deletedGroupID',
    false,
    :'communityID',
    true,
    :'groupCategoryID',
    'Deleted Group',
    'deleted-group'
), (
    :'inactiveCommunityGroupID',
    true,
    :'inactiveCommunityID',
    false,
    :'inactiveCommunityCategoryID',
    'Inactive Community Group',
    'inactive-community-group'
), (
    :'inactiveGroupID',
    false,
    :'communityID',
    false,
    :'groupCategoryID',
    'Inactive Group',
    'inactive-group'
), (
    :'pendingTeamGroupID',
    true,
    :'communityID',
    false,
    :'groupCategoryID',
    'Pending Group',
    'pending-group'
), (
    :'teamGroupID',
    true,
    :'communityID',
    false,
    :'groupCategoryID',
    'Team Group',
    'team-group'
);

-- Membership relationships including hidden groups and a duplicate team group
insert into group_member (
    group_id,
    user_id,
    created_at
) values (
    :'deletedGroupID',
    :'userID',
    '2024-01-06 10:00:00+00'
), (
    :'inactiveGroupID',
    :'userID',
    '2024-01-07 10:00:00+00'
), (
    :'inactiveCommunityGroupID',
    :'userID',
    '2024-01-08 10:00:00+00'
), (
    :'memberGroupID',
    :'userID',
    '2024-01-02 10:00:00+00'
), (
    :'memberTeamGroupID',
    :'userID',
    '2024-01-04 10:00:00+00'
);

-- Accepted and pending team relationships
insert into group_team (
    group_id,
    user_id,
    accepted,
    created_at,
    role
) values (
    :'memberTeamGroupID',
    :'userID',
    true,
    '2024-01-03 10:00:00+00',
    'admin'
), (
    :'pendingTeamGroupID',
    :'userID',
    false,
    '2024-01-08 10:00:00+00',
    'admin'
), (
    :'teamGroupID',
    :'userID',
    true,
    '2024-01-05 10:00:00+00',
    'admin'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list visible member and accepted team groups in name order
select results_eq(
    $$
        select
            item->'group'->>'name',
            item->'group'->>'community_display_name',
            (item->>'is_member')::boolean,
            (item->>'is_team_member')::boolean,
            (item->>'joined_at')::bigint
        from jsonb_array_elements(
            list_user_dashboard_groups(
                '4a0d0000-0000-0000-0000-000000000010'::uuid,
                '{"limit": 10, "offset": 0}'::jsonb
            )::jsonb->'groups'
        ) with ordinality as rows(item, position)
        order by position
    $$,
    $$
        values
            ('Alpha Group'::text, 'User Groups Community'::text, true, false, 1704189600::bigint),
            ('Beta Group'::text, 'User Groups Community'::text, true, true, 1704276000::bigint),
            ('Team Group'::text, 'User Groups Community'::text, false, true, 1704448800::bigint)
    $$,
    'Should list visible member and accepted team groups in name order'
);

-- Should preserve the total while paginating groups
select is(
    (
        list_user_dashboard_groups(
            :'userID'::uuid,
            '{"limit": 1, "offset": 1}'::jsonb
        )::jsonb->>'total'
    )::int,
    3,
    'Should preserve the total while paginating groups'
);

-- Should select the requested page in name order
select is(
    list_user_dashboard_groups(
        :'userID'::uuid,
        '{"limit": 1, "offset": 1}'::jsonb
    )::jsonb#>>'{groups,0,group,name}',
    'Beta Group',
    'Should select the requested page in name order'
);

-- Should return an empty result for a user without group relationships
select is(
    list_user_dashboard_groups(
        :'emptyUserID'::uuid,
        '{"limit": 10, "offset": 0}'::jsonb
    )::jsonb,
    '{"groups": [], "total": 0}'::jsonb,
    'Should return an empty result for a user without group relationships'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
