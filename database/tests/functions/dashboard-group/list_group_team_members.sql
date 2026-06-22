-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a250000-0000-0000-0000-000000000001'
\set groupCategoryID '3a250000-0000-0000-0000-000000000002'
\set groupID '3a250000-0000-0000-0000-000000000003'
\set missingGroupID '3a250000-0000-0000-0000-000000000004'
\set user1ID '3a250000-0000-0000-0000-000000000005'
\set user2ID '3a250000-0000-0000-0000-000000000006'

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
    company,
    name,
    title
) values (
    :'user1ID',
    gen_random_bytes(32),
    'alice@example.com',
    true,
    'alice',
    'Cloud Corp',
    'Alice',
    'Organizer'
), (
    :'user2ID',
    gen_random_bytes(32),
    'bob@example.com',
    true,
    'bob',
    null,
    null,
    null
);

-- Group team membership
insert into group_team (group_id, user_id, role, accepted)
values
    (:'groupID', :'user1ID', 'admin', true),
    (:'groupID', :'user2ID', 'admin', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return list of group team members with accepted flag
select is(
    list_group_team_members(
        :'groupID'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'members', jsonb_build_array(
            jsonb_build_object(
                'accepted', true,
                'company', 'Cloud Corp',
                'name', 'Alice',
                'photo_url', null,
                'role', 'admin',
                'title', 'Organizer',
                'user_id', :'user1ID'::uuid,
                'username', 'alice'
            ),
            jsonb_build_object(
                'accepted', false,
                'company', null,
                'name', null,
                'photo_url', null,
                'role', 'admin',
                'title', null,
                'user_id', :'user2ID'::uuid,
                'username', 'bob'
            )
        ),
        'total', 2,
        'total_accepted', 1,
        'total_admins_accepted', 1
    ),
    'Should return list of group team members with accepted flag'
);

-- Should return paginated team members when limit and offset are provided
select is(
    list_group_team_members(
        :'groupID'::uuid,
        '{"limit": 1, "offset": 1}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'members', jsonb_build_array(
            jsonb_build_object(
                'accepted', false,
                'company', null,
                'name', null,
                'photo_url', null,
                'role', 'admin',
                'title', null,
                'user_id', :'user2ID'::uuid,
                'username', 'bob'
            )
        ),
        'total', 2,
        'total_accepted', 1,
        'total_admins_accepted', 1
    ),
    'Should return paginated team members when limit and offset are provided'
);

-- Should return empty list for non-existing group
select is(
    list_group_team_members(
        :'missingGroupID'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'members', '[]'::jsonb,
        'total', 0,
        'total_accepted', 0,
        'total_admins_accepted', 0
    ),
    'Should return empty list for non-existing group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
