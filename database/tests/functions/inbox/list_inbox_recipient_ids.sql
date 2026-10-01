-- Tests listing the group team members emailed when a user writes to a group.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adminID '1b120000-0000-0000-0000-000000000001'
\set checkInManagerID '1b120000-0000-0000-0000-000000000002'
\set communityAdminID '1b120000-0000-0000-0000-000000000003'
\set communityID '1b120000-0000-0000-0000-000000000004'
\set eventsManagerID '1b120000-0000-0000-0000-000000000005'
\set groupCategoryID '1b120000-0000-0000-0000-000000000006'
\set groupID '1b120000-0000-0000-0000-000000000007'
\set pendingAdminID '1b120000-0000-0000-0000-000000000008'
\set quietGroupID '1b120000-0000-0000-0000-000000000009'
\set unverifiedAdminID '1b120000-0000-0000-0000-000000000010'
\set viewerID '1b120000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Accepted group admin
select fx_user(:'adminID');

-- Accepted check-in manager
select fx_user(:'checkInManagerID');

-- Community admin without a group team membership
select fx_user(:'communityAdminID');

-- Accepted events manager
select fx_user(:'eventsManagerID');

-- Invited group admin who has not accepted yet
select fx_user(:'pendingAdminID');

-- Accepted group admin whose email is not verified
select fx_user(:'unverifiedAdminID', jsonb_build_object('email_verified', false));

-- Accepted viewer
select fx_user(:'viewerID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group receiving inbox messages
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group without inbox recipients
select fx_group(:'quietGroupID', :'communityID', :'groupCategoryID');

-- Community team membership of the community admin
insert into community_team (accepted, community_id, role, user_id)
values (true, :'communityID', 'admin', :'communityAdminID');

-- Group team memberships in every role and state
insert into group_team (accepted, group_id, role, user_id) values
    (true, :'groupID', 'admin', :'adminID'),
    (true, :'groupID', 'check-in-manager', :'checkInManagerID'),
    (true, :'groupID', 'events-manager', :'eventsManagerID'),
    (false, :'groupID', 'admin', :'pendingAdminID'),
    (true, :'groupID', 'admin', :'unverifiedAdminID'),
    (true, :'groupID', 'viewer', :'viewerID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list accepted verified admins and events managers
select is(
    list_inbox_recipient_ids(:'groupID'::uuid),
    array[:'adminID'::uuid, :'eventsManagerID'::uuid],
    'Should list accepted verified admins and events managers'
);

-- Should return an empty list for a group without recipients
select is(
    list_inbox_recipient_ids(:'quietGroupID'::uuid),
    array[]::uuid[],
    'Should return an empty list for a group without recipients'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
