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
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url,
    og_image_url
) values (
    :'community1ID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png',
    'https://example.com/community-og.png'
), (
    :'community2ID',
    'devops-nyc',
    'DevOps NYC',
    'DevOps practitioners in New York City',
    'https://example.com/banner_mobile2.png',
    'https://example.com/banner2.png',
    'https://example.com/logo2.png',
    'https://example.com/community-og2.png'
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'communityAdminUserID',
    gen_random_bytes(32),
    'communityadmin@example.com',
    true,
    'communityadmin',
    'Community Admin User'
), (
    :'dualRoleUserID',
    gen_random_bytes(32),
    'dualrole@example.com',
    true,
    'dualrole',
    'Dual Role User'
), (
    :'groupMemberUserID',
    gen_random_bytes(32),
    'groupmember@example.com',
    true,
    'groupmember',
    'Group Member User'
), (
    :'multiCommunityUserID',
    gen_random_bytes(32),
    'multicommunity@example.com',
    true,
    'multicommunity',
    'Multi Community User'
), (
    :'regularUserID',
    gen_random_bytes(32),
    'regular@example.com',
    true,
    'regularuser',
    'Regular User'
);

-- Group categories
insert into group_category (
    group_category_id,
    community_id,
    name,
    "order"
) values
    (:'groupCategory1ID', :'community1ID', 'Test Category', 1),
    (:'groupCategory2ID', :'community2ID', 'DevOps Category', 1);

-- Groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    city,
    country_code,
    country_name,
    created_at,
    slug_pretty
) values (
    :'group1ID',
    :'community1ID',
    :'groupCategory1ID',
    'Group A',
    'abc1234',
    'Test City',
    'US',
    'United States',
    '2024-01-01 10:00:00+00',
    'group-a'
), (
    :'group2ID',
    :'community1ID',
    :'groupCategory1ID',
    'Group B',
    'def5678',
    'Test City',
    'US',
    'United States',
    '2024-01-02 10:00:00+00',
    null
), (
    :'group3ID',
    :'community1ID',
    :'groupCategory1ID',
    'Group C',
    'ghi9abc',
    'Test City',
    'US',
    'United States',
    '2024-01-03 10:00:00+00',
    null
), (
    :'group4ID',
    :'community1ID',
    :'groupCategory1ID',
    'Group D (Deleted)',
    'jkl2def',
    'Test City',
    'US',
    'United States',
    '2024-01-04 10:00:00+00',
    null
), (
    :'group5ID',
    :'community2ID',
    :'groupCategory2ID',
    'NYC DevOps Meetup',
    'mno3ghi',
    'New York',
    'US',
    'United States',
    '2024-01-05 10:00:00+00',
    null
);

-- Mark group4 as deleted (must also set active = false per check constraint)
update "group" set deleted = true, active = false where group_id = :'group4ID';

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
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle",
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
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle",
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
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle",
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
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle",
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
