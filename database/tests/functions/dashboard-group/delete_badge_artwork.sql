-- Tests removing artwork from a group badge gallery.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'b1070000-0000-0000-0000-000000000001'
\set artworkFreeID 'b1070000-0000-0000-0000-000000000002'
\set artworkUsedID 'b1070000-0000-0000-0000-000000000003'
\set badgeID 'b1070000-0000-0000-0000-000000000004'
\set communityID 'b1070000-0000-0000-0000-000000000005'
\set groupCategoryID 'b1070000-0000-0000-0000-000000000006'
\set groupID 'b1070000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================


-- Community that owns the artwork
select fx_community(:'communityID', jsonb_build_object('description', 'Description'));

-- Baseline categories, users and groups
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'actorID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Referenced and unreferenced gallery entries
insert into badge_artwork (badge_artwork_id, file_name, group_id)
values
    (:'artworkFreeID', 'free.png', :'groupID'),
    (:'artworkUsedID', 'used.png', :'groupID');

-- Definition that protects the referenced gallery entry
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'badgeID', 'Criteria', 'Description', :'groupID', 'used.png', 'Badge');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block artwork referenced by a current definition
select throws_ok(
    format($$select delete_badge_artwork(%L::uuid, %L::uuid, %L::uuid, %L::uuid)$$, :'actorID', :'communityID', :'groupID', :'artworkUsedID'),
    'OCG01',
    'badge artwork is used by a badge',
    'Should block artwork referenced by a current definition'
);

-- Should remove an unreferenced gallery entry
select lives_ok(
    format($$select delete_badge_artwork(%L::uuid, %L::uuid, %L::uuid, %L::uuid)$$, :'actorID', :'communityID', :'groupID', :'artworkFreeID'),
    'Should remove an unreferenced gallery entry'
);

-- Should persist and audit the gallery removal
select ok(
    not exists (select 1 from badge_artwork where badge_artwork_id = :'artworkFreeID')
    and exists (
        select 1 from audit_log
        where action = 'badge_artwork_deleted'
        and details = '{"file_name":"free.png"}'::jsonb
    ),
    'Should persist and audit the gallery removal'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
