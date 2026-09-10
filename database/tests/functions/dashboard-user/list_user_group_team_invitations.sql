-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a020000-0000-0000-0000-000000000001'
\set communityOtherID '4a020000-0000-0000-0000-000000000002'
\set groupAcceptedID '4a020000-0000-0000-0000-000000000003'
\set groupCategoryID '4a020000-0000-0000-0000-000000000004'
\set groupCategoryOtherID '4a020000-0000-0000-0000-000000000005'
\set groupID '4a020000-0000-0000-0000-000000000006'
\set groupOtherID '4a020000-0000-0000-0000-000000000007'
\set userID '4a020000-0000-0000-0000-000000000008'
\set userNoInvitationsID '4a020000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities named in invitation payloads
select fx_community(:'communityID', jsonb_build_object('name', 'community-one-group-team-invitations'));
select fx_community(:'communityOtherID', jsonb_build_object('name', 'community-two-group-team-invitations'));

-- Baseline group categories, users and groups
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group_category(:'groupCategoryOtherID', :'communityOtherID');
select fx_user(:'userID');
select fx_user(:'userNoInvitationsID');
select fx_group(:'groupAcceptedID', :'communityID', :'groupCategoryID');

-- Groups named in invitation payloads
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Group One'));

select fx_group(:'groupOtherID', :'communityOtherID', :'groupCategoryOtherID', jsonb_build_object('name', 'Group Three'));

-- Pending and accepted group invitations used by listing scenarios
insert into group_team (group_id, user_id, role, accepted, created_at) values
    (:'groupID', :'userID', 'admin', false, '2024-01-02 10:00:00+00'),
    (:'groupAcceptedID', :'userID', 'admin', true, '2024-01-03 10:00:00+00'),
    (:'groupOtherID', :'userID', 'admin', false, '2024-01-04 10:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list all pending invitations for a user across all communities
select is(
    list_user_group_team_invitations(:'userID'::uuid)::jsonb,
    format(
        $json$
            [
                {
                    "community_name": "community-two-group-team-invitations",
                    "group_id": "%s",
                    "group_name": "Group Three",
                    "role": "admin",
                    "created_at": 1704362400
                },
                {
                    "community_name": "community-one-group-team-invitations",
                    "group_id": "%s",
                    "group_name": "Group One",
                    "role": "admin",
                    "created_at": 1704189600
                }
            ]
        $json$,
        :'groupOtherID',
        :'groupID'
    )::jsonb,
    'Should list all pending invitations for the user ordered by created_at desc'
);

-- Should return empty list when no pending invites present for a user
select is(
    list_user_group_team_invitations(:'userNoInvitationsID'::uuid)::text,
    '[]',
    'No invitations should result in empty list'
);

-- Should not return accepted invitations
update group_team
set accepted = true
where group_id = :'groupOtherID'
  and user_id = :'userID';
select is(
    list_user_group_team_invitations(:'userID'::uuid)::jsonb,
    format(
        $json$
            [
                {
                    "community_name": "community-one-group-team-invitations",
                    "group_id": "%s",
                    "group_name": "Group One",
                    "role": "admin",
                    "created_at": 1704189600
                }
            ]
        $json$,
        :'groupID'
    )::jsonb,
    'Should not return accepted invitations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
