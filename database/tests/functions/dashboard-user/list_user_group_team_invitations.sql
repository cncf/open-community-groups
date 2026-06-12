-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a0d0000-0000-0000-0000-000000000001'
\set communityOtherID '4a0d0000-0000-0000-0000-000000000002'
\set groupAcceptedID '4a0d0000-0000-0000-0000-000000000003'
\set groupCategoryID '4a0d0000-0000-0000-0000-000000000004'
\set groupCategoryOtherID '4a0d0000-0000-0000-0000-000000000005'
\set groupID '4a0d0000-0000-0000-0000-000000000006'
\set groupOtherID '4a0d0000-0000-0000-0000-000000000007'
\set userID '4a0d0000-0000-0000-0000-000000000008'
\set userNoInvitationsID '4a0d0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'community-one',
    'Community One',
    'Primary community with pending group invitations',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
), (
    :'communityOtherID',
    'community-two',
    'Community Two',
    'Secondary community with pending group invitations',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group categories
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategoryID', :'communityID', 'Technology'),
    (:'groupCategoryOtherID', :'communityOtherID', 'Design');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'userID',
    gen_random_bytes(32),
    'alice@example.com',
    true,
    'alice',
    'Alice'
), (
    :'userNoInvitationsID',
    gen_random_bytes(32),
    'bob@example.com',
    true,
    'bob',
    'Bob'
);

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Group One', 'group-one'),
    (:'groupAcceptedID', :'communityID', :'groupCategoryID', 'Group Two', 'group-two'),
    (:'groupOtherID', :'communityOtherID', :'groupCategoryOtherID', 'Group Three', 'group-three');

-- Pending group invitations (two in main community, one in other community)
insert into group_team (group_id, user_id, role, accepted, created_at) values
    (:'groupID', :'userID', 'admin', false, '2024-01-02 10:00:00+00'),
    (:'groupAcceptedID', :'userID', 'admin', false, '2024-01-03 10:00:00+00'),
    (:'groupOtherID', :'userID', 'admin', false, '2024-01-04 10:00:00+00');

-- Accepted membership should not be listed (mark existing invite as accepted)
update group_team
set accepted = true
where group_id = :'groupAcceptedID'
  and user_id = :'userID';

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
                    "community_name": "community-two",
                    "group_id": "%s",
                    "group_name": "Group Three",
                    "role": "admin",
                    "created_at": 1704362400
                },
                {
                    "community_name": "community-one",
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
                    "community_name": "community-one",
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
