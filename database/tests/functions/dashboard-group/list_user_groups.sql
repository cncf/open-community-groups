-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000021'
\set category2ID '00000000-0000-0000-0000-000000000022'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityAdminUserID '00000000-0000-0000-0000-000000000013'
\set dualRoleUserID '00000000-0000-0000-0000-000000000014'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'
\set group4ID '00000000-0000-0000-0000-000000000034'
\set group5ID '00000000-0000-0000-0000-000000000035'
\set groupMemberUserID '00000000-0000-0000-0000-000000000011'
\set multiCommunityUserID '00000000-0000-0000-0000-000000000015'
\set regularUserID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (:'community1ID', 'cloud-native-seattle', 'Cloud Native Seattle', 'A vibrant community for cloud native technologies and practices in Seattle', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png'),
    (:'community2ID', 'devops-nyc', 'DevOps NYC', 'DevOps practitioners in New York City', 'https://example.com/logo2.png', 'https://example.com/banner_mobile2.png', 'https://example.com/banner2.png');

-- User
insert into "user" (
    user_id,
    auth_hash,
    email,
    name,
    username,
    email_verified
) values
    (:'communityAdminUserID', gen_random_bytes(32), 'communityadmin@example.com', 'Community Admin User', 'communityadmin', true),
    (:'dualRoleUserID', gen_random_bytes(32), 'dualrole@example.com', 'Dual Role User', 'dualrole', true),
    (:'groupMemberUserID', gen_random_bytes(32), 'groupmember@example.com', 'Group Member User', 'groupmember', true),
    (:'multiCommunityUserID', gen_random_bytes(32), 'multicommunity@example.com', 'Multi Community User', 'multicommunity', true),
    (:'regularUserID', gen_random_bytes(32), 'regular@example.com', 'Regular User', 'regularuser', true);

-- Group Category
insert into group_category (
    group_category_id,
    community_id,
    name,
    "order"
) values
    (:'category1ID', :'community1ID', 'Test Category', 1),
    (:'category2ID', :'community2ID', 'DevOps Category', 1);

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    created_at,
    city,
    country_code,
    country_name
) values
    (:'group1ID', :'community1ID', :'category1ID', 'Group A', 'abc1234', '2024-01-01 10:00:00+00', 'Test City', 'US', 'United States'),
    (:'group2ID', :'community1ID', :'category1ID', 'Group B', 'def5678', '2024-01-02 10:00:00+00', 'Test City', 'US', 'United States'),
    (:'group3ID', :'community1ID', :'category1ID', 'Group C', 'ghi9abc', '2024-01-03 10:00:00+00', 'Test City', 'US', 'United States'),
    (:'group4ID', :'community1ID', :'category1ID', 'Group D (Deleted)', 'jkl2def', '2024-01-04 10:00:00+00', 'Test City', 'US', 'United States'),
    (:'group5ID', :'community2ID', :'category2ID', 'NYC DevOps Meetup', 'mno3ghi', '2024-01-05 10:00:00+00', 'New York', 'US', 'United States');

-- Mark group4 as deleted (must also set active = false per check constraint)
update "group" set deleted = true, active = false where group_id = :'group4ID';

-- Group Team
insert into group_team (group_id, user_id, role, accepted) values
    (:'group1ID', :'groupMemberUserID', 'organizer', true),
    (:'group1ID', :'multiCommunityUserID', 'organizer', true),
    (:'group2ID', :'groupMemberUserID', 'organizer', true),
    (:'group5ID', :'multiCommunityUserID', 'organizer', true);

-- Community Team
insert into community_team (accepted, community_id, user_id) values
    (true, :'community1ID', :'communityAdminUserID');

-- Community Team (dual membership)
insert into community_team (accepted, community_id, user_id) values
    (true, :'community1ID', :'dualRoleUserID');
insert into group_team (group_id, user_id, role, accepted) values
    (:'group2ID', :'dualRoleUserID', 'organizer', true);


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
                "community_id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle"
            },
            "groups": [
                {
                    "active": true,
                    "category": {
                        "group_category_id": "00000000-0000-0000-0000-000000000021",
                        "name": "Test Category",
                        "normalized_name": "test-category",
                        "order": 1
                    },
                    "community_display_name": "Cloud Native Seattle",
                    "community_name": "cloud-native-seattle",
                    "created_at": 1704103200,
                    "group_id": "00000000-0000-0000-0000-000000000031",
                    "name": "Group A",
                    "slug": "abc1234",
                    "city": "Test City",
                    "country_code": "US",
                    "country_name": "United States"
                },
                {
                    "active": true,
                    "category": {
                        "group_category_id": "00000000-0000-0000-0000-000000000021",
                        "name": "Test Category",
                        "normalized_name": "test-category",
                        "order": 1
                    },
                    "community_display_name": "Cloud Native Seattle",
                    "community_name": "cloud-native-seattle",
                    "created_at": 1704189600,
                    "group_id": "00000000-0000-0000-0000-000000000032",
                    "name": "Group B",
                    "slug": "def5678",
                    "city": "Test City",
                    "country_code": "US",
                    "country_name": "United States"
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
                "community_id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle"
            },
            "groups": [
                {
                    "active": true,
                    "category": {
                        "group_category_id": "00000000-0000-0000-0000-000000000021",
                        "name": "Test Category",
                        "normalized_name": "test-category",
                        "order": 1
                    },
                    "community_display_name": "Cloud Native Seattle",
                    "community_name": "cloud-native-seattle",
                    "created_at": 1704103200,
                    "group_id": "00000000-0000-0000-0000-000000000031",
                    "name": "Group A",
                    "slug": "abc1234",
                    "city": "Test City",
                    "country_code": "US",
                    "country_name": "United States"
                },
                {
                    "active": true,
                    "category": {
                        "group_category_id": "00000000-0000-0000-0000-000000000021",
                        "name": "Test Category",
                        "normalized_name": "test-category",
                        "order": 1
                    },
                    "community_display_name": "Cloud Native Seattle",
                    "community_name": "cloud-native-seattle",
                    "created_at": 1704189600,
                    "group_id": "00000000-0000-0000-0000-000000000032",
                    "name": "Group B",
                    "slug": "def5678",
                    "city": "Test City",
                    "country_code": "US",
                    "country_name": "United States"
                },
                {
                    "active": true,
                    "category": {
                        "group_category_id": "00000000-0000-0000-0000-000000000021",
                        "name": "Test Category",
                        "normalized_name": "test-category",
                        "order": 1
                    },
                    "community_display_name": "Cloud Native Seattle",
                    "community_name": "cloud-native-seattle",
                    "created_at": 1704276000,
                    "group_id": "00000000-0000-0000-0000-000000000033",
                    "name": "Group C",
                    "slug": "ghi9abc",
                    "city": "Test City",
                    "country_code": "US",
                    "country_name": "United States"
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
                "community_id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle"
            },
            "groups": [
                {
                    "active": true,
                    "category": {
                        "group_category_id": "00000000-0000-0000-0000-000000000021",
                        "name": "Test Category",
                        "normalized_name": "test-category",
                        "order": 1
                    },
                    "community_display_name": "Cloud Native Seattle",
                    "community_name": "cloud-native-seattle",
                    "created_at": 1704103200,
                    "group_id": "00000000-0000-0000-0000-000000000031",
                    "name": "Group A",
                    "slug": "abc1234",
                    "city": "Test City",
                    "country_code": "US",
                    "country_name": "United States"
                },
                {
                    "active": true,
                    "category": {
                        "group_category_id": "00000000-0000-0000-0000-000000000021",
                        "name": "Test Category",
                        "normalized_name": "test-category",
                        "order": 1
                    },
                    "community_display_name": "Cloud Native Seattle",
                    "community_name": "cloud-native-seattle",
                    "created_at": 1704189600,
                    "group_id": "00000000-0000-0000-0000-000000000032",
                    "name": "Group B",
                    "slug": "def5678",
                    "city": "Test City",
                    "country_code": "US",
                    "country_name": "United States"
                },
                {
                    "active": true,
                    "category": {
                        "group_category_id": "00000000-0000-0000-0000-000000000021",
                        "name": "Test Category",
                        "normalized_name": "test-category",
                        "order": 1
                    },
                    "community_display_name": "Cloud Native Seattle",
                    "community_name": "cloud-native-seattle",
                    "created_at": 1704276000,
                    "group_id": "00000000-0000-0000-0000-000000000033",
                    "name": "Group C",
                    "slug": "ghi9abc",
                    "city": "Test City",
                    "country_code": "US",
                    "country_name": "United States"
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
                "community_id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle"
            },
            "groups": [
                {
                    "active": true,
                    "category": {
                        "group_category_id": "00000000-0000-0000-0000-000000000021",
                        "name": "Test Category",
                        "normalized_name": "test-category",
                        "order": 1
                    },
                    "community_display_name": "Cloud Native Seattle",
                    "community_name": "cloud-native-seattle",
                    "created_at": 1704103200,
                    "group_id": "00000000-0000-0000-0000-000000000031",
                    "name": "Group A",
                    "slug": "abc1234",
                    "city": "Test City",
                    "country_code": "US",
                    "country_name": "United States"
                }
            ]
        },
        {
            "community": {
                "banner_mobile_url": "https://example.com/banner_mobile2.png",
                "banner_url": "https://example.com/banner2.png",
                "community_id": "00000000-0000-0000-0000-000000000002",
                "display_name": "DevOps NYC",
                "logo_url": "https://example.com/logo2.png",
                "name": "devops-nyc"
            },
            "groups": [
                {
                    "active": true,
                    "category": {
                        "group_category_id": "00000000-0000-0000-0000-000000000022",
                        "name": "DevOps Category",
                        "normalized_name": "devops-category",
                        "order": 1
                    },
                    "community_display_name": "DevOps NYC",
                    "community_name": "devops-nyc",
                    "created_at": 1704448800,
                    "group_id": "00000000-0000-0000-0000-000000000035",
                    "name": "NYC DevOps Meetup",
                    "slug": "mno3ghi",
                    "city": "New York",
                    "country_code": "US",
                    "country_name": "United States"
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
