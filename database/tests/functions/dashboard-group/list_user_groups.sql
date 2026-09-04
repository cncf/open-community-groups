-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '3a290000-0000-0000-0000-000000000001'
\set community2ID '3a290000-0000-0000-0000-000000000002'
\set communityAdminUserID '3a290000-0000-0000-0000-000000000003'
\set dualRoleUserID '3a290000-0000-0000-0000-000000000004'
\set group1ID '3a290000-0000-0000-0000-000000000005'
\set group2ID '3a290000-0000-0000-0000-000000000006'
\set group3ID '3a290000-0000-0000-0000-000000000007'
\set group4ID '3a290000-0000-0000-0000-000000000008'
\set group5ID '3a290000-0000-0000-0000-000000000009'
\set groupCategory1ID '3a290000-0000-0000-0000-000000000010'
\set groupCategory2ID '3a290000-0000-0000-0000-000000000011'
\set groupMemberUserID '3a290000-0000-0000-0000-000000000012'
\set multiCommunityUserID '3a290000-0000-0000-0000-000000000013'
\set regularUserID '3a290000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'community1ID', jsonb_build_object(
    'banner_mobile_url', 'https://example.com/banner_mobile.png',
    'banner_url', 'https://example.com/banner.png',
    'display_name', 'Cloud Native Seattle List User Groups',
    'logo_url', 'https://example.com/logo.png',
    'name', 'cloud-native-seattle-list-user-groups',
    'og_image_url', 'https://example.com/community-og.png'
));
select fx_community(:'community2ID', jsonb_build_object(
    'banner_mobile_url', 'https://example.com/banner_mobile2.png',
    'banner_url', 'https://example.com/banner2.png',
    'display_name', 'DevOps NYC',
    'logo_url', 'https://example.com/logo2.png',
    'name', 'devops-nyc',
    'og_image_url', 'https://example.com/community-og2.png'
));

-- Baseline users
select fx_user(:'communityAdminUserID');
select fx_user(:'dualRoleUserID');
select fx_user(:'groupMemberUserID');
select fx_user(:'multiCommunityUserID');
select fx_user(:'regularUserID');

-- Group categories
select fx_group_category(:'groupCategory1ID', :'community1ID');
select fx_group_category(:'groupCategory2ID', :'community2ID');

-- Groups
select fx_group(:'group1ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'Test City',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-01 10:00:00+00',
    'name', 'Group A',
    'slug', 'abc1234',
    'slug_pretty', 'group-a'
));
select fx_group(:'group2ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'Test City',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-02 10:00:00+00',
    'name', 'Group B',
    'slug', 'def5678'
));
select fx_group(:'group3ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'Test City',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-03 10:00:00+00',
    'name', 'Group C',
    'slug', 'ghi9abc'
));
select fx_group(:'group4ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'active', false,
    'city', 'Test City',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-04 10:00:00+00',
    'deleted', true
));
select fx_group(:'group5ID', :'community2ID', :'groupCategory2ID', jsonb_build_object(
    'city', 'New York',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-05 10:00:00+00',
    'name', 'NYC DevOps Meetup',
    'slug', 'mno3ghi'
));

-- Group Team
insert into group_team (group_id, user_id, role, accepted) values
    (:'group1ID', :'groupMemberUserID', 'admin', true),
    (:'group1ID', :'multiCommunityUserID', 'admin', true),
    (:'group2ID', :'groupMemberUserID', 'admin', true),
    (:'group5ID', :'multiCommunityUserID', 'admin', true);

-- Community Team
insert into community_team (accepted, community_id, role, user_id) values
    (true, :'community1ID', 'admin', :'communityAdminUserID');

-- Community Team (dual membership)
insert into community_team (accepted, community_id, role, user_id) values
    (true, :'community1ID', 'admin', :'dualRoleUserID');

-- Group membership held by the same dual-role user
insert into group_team (group_id, user_id, role, accepted) values
    (:'group2ID', :'dualRoleUserID', 'admin', true);


-- ============================================================================
-- TESTS
-- ============================================================================

-- Should see empty array for user without any team memberships
select is(
    list_user_groups(:'regularUserID'::uuid)::text,
    '[]',
    'Regular user without any team memberships should see empty array'
);

-- Should see only groups where they are members for group team member
select is(
    list_user_groups(:'groupMemberUserID'::uuid)::jsonb,
    '[
        {
            "community": {
                "banner_mobile_url": "https://example.com/banner_mobile.png",
                "banner_url": "https://example.com/banner.png",
                "community_id": "3a290000-0000-0000-0000-000000000001",
                "display_name": "Cloud Native Seattle List User Groups",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle-list-user-groups",
                "og_image_url": "https://example.com/community-og.png"
            },
            "groups": [
                {
                    "active": true,
                    "group_id": "3a290000-0000-0000-0000-000000000005",
                    "name": "Group A",
                    "slug": "abc1234",
                    "slug_pretty": "group-a"
                },
                {
                    "active": true,
                    "group_id": "3a290000-0000-0000-0000-000000000006",
                    "name": "Group B",
                    "slug": "def5678"
                }
            ]
        }
    ]'::jsonb,
    'Group team member (not in community team) should see only groups A and B where they are members'
);

-- Should see all non-deleted groups for community team member
select is(
    list_user_groups(:'communityAdminUserID'::uuid)::jsonb,
    '[
        {
            "community": {
                "banner_mobile_url": "https://example.com/banner_mobile.png",
                "banner_url": "https://example.com/banner.png",
                "community_id": "3a290000-0000-0000-0000-000000000001",
                "display_name": "Cloud Native Seattle List User Groups",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle-list-user-groups",
                "og_image_url": "https://example.com/community-og.png"
            },
            "groups": [
                {
                    "active": true,
                    "group_id": "3a290000-0000-0000-0000-000000000005",
                    "name": "Group A",
                    "slug": "abc1234",
                    "slug_pretty": "group-a"
                },
                {
                    "active": true,
                    "group_id": "3a290000-0000-0000-0000-000000000006",
                    "name": "Group B",
                    "slug": "def5678"
                },
                {
                    "active": true,
                    "group_id": "3a290000-0000-0000-0000-000000000007",
                    "name": "Group C",
                    "slug": "ghi9abc"
                }
            ]
        }
    ]'::jsonb,
    'Community team member (not in any group teams) should see all three non-deleted groups (A, B, C)'
);

-- Should see all groups without duplicates for dual role user
select is(
    list_user_groups(:'dualRoleUserID'::uuid)::jsonb,
    '[
        {
            "community": {
                "banner_mobile_url": "https://example.com/banner_mobile.png",
                "banner_url": "https://example.com/banner.png",
                "community_id": "3a290000-0000-0000-0000-000000000001",
                "display_name": "Cloud Native Seattle List User Groups",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle-list-user-groups",
                "og_image_url": "https://example.com/community-og.png"
            },
            "groups": [
                {
                    "active": true,
                    "group_id": "3a290000-0000-0000-0000-000000000005",
                    "name": "Group A",
                    "slug": "abc1234",
                    "slug_pretty": "group-a"
                },
                {
                    "active": true,
                    "group_id": "3a290000-0000-0000-0000-000000000006",
                    "name": "Group B",
                    "slug": "def5678"
                },
                {
                    "active": true,
                    "group_id": "3a290000-0000-0000-0000-000000000007",
                    "name": "Group C",
                    "slug": "ghi9abc"
                }
            ]
        }
    ]'::jsonb,
    'User with both community and group team memberships should see all groups without duplicates (Group B not duplicated)'
);

-- Should see groups from multiple communities sorted by community name
select is(
    list_user_groups(:'multiCommunityUserID'::uuid)::jsonb,
    '[
        {
            "community": {
                "banner_mobile_url": "https://example.com/banner_mobile.png",
                "banner_url": "https://example.com/banner.png",
                "community_id": "3a290000-0000-0000-0000-000000000001",
                "display_name": "Cloud Native Seattle List User Groups",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle-list-user-groups",
                "og_image_url": "https://example.com/community-og.png"
            },
            "groups": [
                {
                    "active": true,
                    "group_id": "3a290000-0000-0000-0000-000000000005",
                    "name": "Group A",
                    "slug": "abc1234",
                    "slug_pretty": "group-a"
                }
            ]
        },
        {
            "community": {
                "banner_mobile_url": "https://example.com/banner_mobile2.png",
                "banner_url": "https://example.com/banner2.png",
                "community_id": "3a290000-0000-0000-0000-000000000002",
                "display_name": "DevOps NYC",
                "logo_url": "https://example.com/logo2.png",
                "name": "devops-nyc",
                "og_image_url": "https://example.com/community-og2.png"
            },
            "groups": [
                {
                    "active": true,
                    "group_id": "3a290000-0000-0000-0000-000000000009",
                    "name": "NYC DevOps Meetup",
                    "slug": "mno3ghi"
                }
            ]
        }
    ]'::jsonb,
    'User with group team memberships in multiple communities should see groups from both communities sorted by community name'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
