-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a250000-0000-0000-0000-000000000001'
\set groupCategoryID '3a250000-0000-0000-0000-000000000002'
\set groupID '3a250000-0000-0000-0000-000000000003'
\set missingGroupID '3a250000-0000-0000-0000-000000000004'
\set user1ID '3a250000-0000-0000-0000-000000000005'
\set user2ID '3a250000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user1ID', jsonb_build_object(
    'company', 'Cloud Corp',
    'name', 'Alice',
    'title', 'Organizer',
    'username', 'alice-list-group-team-members'
));
select fx_user(:'user2ID', jsonb_build_object('username', 'bob-list-group-team-members'));

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
                'username', 'alice-list-group-team-members'
            ),
            jsonb_build_object(
                'accepted', false,
                'company', null,
                'name', null,
                'photo_url', null,
                'role', 'admin',
                'title', null,
                'user_id', :'user2ID'::uuid,
                'username', 'bob-list-group-team-members'
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
                'username', 'bob-list-group-team-members'
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
