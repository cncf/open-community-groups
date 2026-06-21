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
\set alliance1ID '00000000-0000-0000-0000-000000000001'
\set alliance2ID '00000000-0000-0000-0000-000000000002'
\set allianceAdminUserID '00000000-0000-0000-0000-000000000013'
\set dualRoleUserID '00000000-0000-0000-0000-000000000014'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'
\set group4ID '00000000-0000-0000-0000-000000000034'
\set group5ID '00000000-0000-0000-0000-000000000035'
\set groupMemberUserID '00000000-0000-0000-0000-000000000011'
\set multiAllianceUserID '00000000-0000-0000-0000-000000000015'
\set regularUserID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    logo_url,
    og_image_url,
    banner_mobile_url,
    banner_url
) values
    (:'alliance1ID', 'cloud-native-seattle', 'Cloud Native Seattle', 'A vibrant alliance for cloud native technologies and practices in Seattle', 'https://example.com/logo.png', 'https://example.com/alliance-og.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png'),
    (:'alliance2ID', 'devops-nyc', 'DevOps NYC', 'DevOps practitioners in New York City', 'https://example.com/logo2.png', 'https://example.com/alliance-og2.png', 'https://example.com/banner_mobile2.png', 'https://example.com/banner2.png');

-- User
insert into "user" (
    user_id,
    auth_hash,
    email,
    name,
    username,
    email_verified
) values
    (:'allianceAdminUserID', gen_random_bytes(32), 'allianceadmin@example.com', 'Alliance Admin User', 'allianceadmin', true),
    (:'dualRoleUserID', gen_random_bytes(32), 'dualrole@example.com', 'Dual Role User', 'dualrole', true),
    (:'groupMemberUserID', gen_random_bytes(32), 'groupmember@example.com', 'Group Member User', 'groupmember', true),
    (:'multiAllianceUserID', gen_random_bytes(32), 'multialliance@example.com', 'Multi Alliance User', 'multialliance', true),
    (:'regularUserID', gen_random_bytes(32), 'regular@example.com', 'Regular User', 'regularuser', true);

-- Group Category
insert into group_category (
    group_category_id,
    alliance_id,
    name,
    "order"
) values
    (:'category1ID', :'alliance1ID', 'Test Category', 1),
    (:'category2ID', :'alliance2ID', 'DevOps Category', 1);

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    slug_pretty,
    created_at,
    city,
    country_code,
    country_name
) values
    (:'group1ID', :'alliance1ID', :'category1ID', 'Group A', 'abc1234', 'group-a', '2024-01-01 10:00:00+00', 'Test City', 'US', 'United States'),
    (:'group2ID', :'alliance1ID', :'category1ID', 'Group B', 'def5678', null, '2024-01-02 10:00:00+00', 'Test City', 'US', 'United States'),
    (:'group3ID', :'alliance1ID', :'category1ID', 'Group C', 'ghi9abc', null, '2024-01-03 10:00:00+00', 'Test City', 'US', 'United States'),
    (:'group4ID', :'alliance1ID', :'category1ID', 'Group D (Deleted)', 'jkl2def', null, '2024-01-04 10:00:00+00', 'Test City', 'US', 'United States'),
    (:'group5ID', :'alliance2ID', :'category2ID', 'NYC DevOps Meetup', 'mno3ghi', null, '2024-01-05 10:00:00+00', 'New York', 'US', 'United States');

-- Mark group4 as deleted (must also set active = false per check constraint)
update "group" set deleted = true, active = false where group_id = :'group4ID';

-- Group Team
insert into group_team (group_id, user_id, role, accepted) values
    (:'group1ID', :'groupMemberUserID', 'admin', true),
    (:'group1ID', :'multiAllianceUserID', 'admin', true),
    (:'group2ID', :'groupMemberUserID', 'admin', true),
    (:'group5ID', :'multiAllianceUserID', 'admin', true);

-- Alliance Team
insert into alliance_team (accepted, alliance_id, role, user_id) values
    (true, :'alliance1ID', 'admin', :'allianceAdminUserID');

-- Alliance Team (dual membership)
insert into alliance_team (accepted, alliance_id, role, user_id) values
    (true, :'alliance1ID', 'admin', :'dualRoleUserID');
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
            "alliance": {
                "banner_mobile_url": "https://example.com/banner_mobile.png",
                "banner_url": "https://example.com/banner.png",
                "alliance_id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle",
                "og_image_url": "https://example.com/alliance-og.png"
            },
            "groups": [
                {
                    "active": true,
                    "group_id": "00000000-0000-0000-0000-000000000031",
                    "name": "Group A",
                    "slug": "abc1234",
                    "slug_pretty": "group-a"
                },
                {
                    "active": true,
                    "group_id": "00000000-0000-0000-0000-000000000032",
                    "name": "Group B",
                    "slug": "def5678"
                }
            ]
        }
    ]'::jsonb,
    'Group team member (not in alliance team) should see only groups A and B where they are members'
);

-- Should see all non-deleted groups for alliance team member
select is(
    list_user_groups(:'allianceAdminUserID'::uuid)::jsonb,
    '[
        {
            "alliance": {
                "banner_mobile_url": "https://example.com/banner_mobile.png",
                "banner_url": "https://example.com/banner.png",
                "alliance_id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle",
                "og_image_url": "https://example.com/alliance-og.png"
            },
            "groups": [
                {
                    "active": true,
                    "group_id": "00000000-0000-0000-0000-000000000031",
                    "name": "Group A",
                    "slug": "abc1234",
                    "slug_pretty": "group-a"
                },
                {
                    "active": true,
                    "group_id": "00000000-0000-0000-0000-000000000032",
                    "name": "Group B",
                    "slug": "def5678"
                },
                {
                    "active": true,
                    "group_id": "00000000-0000-0000-0000-000000000033",
                    "name": "Group C",
                    "slug": "ghi9abc"
                }
            ]
        }
    ]'::jsonb,
    'Alliance team member (not in any group teams) should see all three non-deleted groups (A, B, C)'
);

-- Should see all groups without duplicates for dual role user
select is(
    list_user_groups(:'dualRoleUserID'::uuid)::jsonb,
    '[
        {
            "alliance": {
                "banner_mobile_url": "https://example.com/banner_mobile.png",
                "banner_url": "https://example.com/banner.png",
                "alliance_id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle",
                "og_image_url": "https://example.com/alliance-og.png"
            },
            "groups": [
                {
                    "active": true,
                    "group_id": "00000000-0000-0000-0000-000000000031",
                    "name": "Group A",
                    "slug": "abc1234",
                    "slug_pretty": "group-a"
                },
                {
                    "active": true,
                    "group_id": "00000000-0000-0000-0000-000000000032",
                    "name": "Group B",
                    "slug": "def5678"
                },
                {
                    "active": true,
                    "group_id": "00000000-0000-0000-0000-000000000033",
                    "name": "Group C",
                    "slug": "ghi9abc"
                }
            ]
        }
    ]'::jsonb,
    'User with both alliance and group team memberships should see all groups without duplicates (Group B not duplicated)'
);

-- Should see groups from multiple alliances sorted by alliance name
select is(
    list_user_groups(:'multiAllianceUserID'::uuid)::jsonb,
    '[
        {
            "alliance": {
                "banner_mobile_url": "https://example.com/banner_mobile.png",
                "banner_url": "https://example.com/banner.png",
                "alliance_id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/logo.png",
                "name": "cloud-native-seattle",
                "og_image_url": "https://example.com/alliance-og.png"
            },
            "groups": [
                {
                    "active": true,
                    "group_id": "00000000-0000-0000-0000-000000000031",
                    "name": "Group A",
                    "slug": "abc1234",
                    "slug_pretty": "group-a"
                }
            ]
        },
        {
            "alliance": {
                "banner_mobile_url": "https://example.com/banner_mobile2.png",
                "banner_url": "https://example.com/banner2.png",
                "alliance_id": "00000000-0000-0000-0000-000000000002",
                "display_name": "DevOps NYC",
                "logo_url": "https://example.com/logo2.png",
                "name": "devops-nyc",
                "og_image_url": "https://example.com/alliance-og2.png"
            },
            "groups": [
                {
                    "active": true,
                    "group_id": "00000000-0000-0000-0000-000000000035",
                    "name": "NYC DevOps Meetup",
                    "slug": "mno3ghi"
                }
            ]
        }
    ]'::jsonb,
    'User with group team memberships in multiple alliances should see groups from both alliances sorted by alliance name'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
