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

-- Baseline actor, community and group that owns the badge
select fx_user(:'actorID');
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

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
    'OCG01',
    'badge artwork not found',
    'Should reject unknown artwork'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
