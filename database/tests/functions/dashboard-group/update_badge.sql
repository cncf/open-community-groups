-- Tests updating group badge definitions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'b1050000-0000-0000-0000-000000000001'
\set badgeID 'b1050000-0000-0000-0000-000000000002'
\set communityID 'b1050000-0000-0000-0000-000000000003'
\set groupCategoryID 'b1050000-0000-0000-0000-000000000004'
\set groupID 'b1050000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Admin authorized to update badges
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'actorID', 'hash', 'update-admin@example.test', true, 'update-admin');

-- Community that owns the badge
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Update Community', '/logo', 'update-community');

-- Category used by the badge group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the badge
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Update Group', 'update-group');

-- Authorized group team member
insert into group_team (group_id, accepted, role, user_id)
values (:'groupID', true, 'events-manager', :'actorID');

-- Current and replacement gallery artwork
insert into badge_artwork (file_name, group_id)
values ('current.png', :'groupID'), ('replacement.png', :'groupID');

-- Existing definition to update
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'badgeID', 'Old criteria', 'Old description', :'groupID', 'current.png', 'Old name');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update the current definition and record audit history
select lives_ok(
    format(
        $$select update_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, '{"criteria":"New criteria","description":"New description","image_file_name":"replacement.png","name":"New name"}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID'
    ),
    'Should update the current definition and record audit history'
);

-- Should persist updated badge fields and audit history
select ok(
    exists (select 1 from badge where badge_id = :'badgeID' and name = 'New name' and image_file_name = 'replacement.png')
    and exists (
        select 1 from audit_log
        where action = 'badge_updated'
        and details = '{"badge_name":"New name"}'::jsonb
        and resource_id = :'badgeID'
    ),
    'Should persist updated badge fields and audit history'
);

-- Should reject unknown artwork
select throws_ok(
    format(
        $$select update_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, '{"criteria":"C","description":"D","image_file_name":"missing.png","name":"N"}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID'
    ),
    'badge artwork not found',
    'Should reject unknown artwork'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
