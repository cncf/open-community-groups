-- Tests removing artwork from a group badge gallery.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

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
select fx_user(:'actorID', jsonb_build_object('username', 'delete-badge-artwork-actor'));
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

-- Should remove only the unreferenced gallery entry
select results_eq(
    $$ select badge_artwork_id from badge_artwork $$,
    format($$ values (%L::uuid) $$, :'artworkUsedID'),
    'Should remove only the unreferenced gallery entry'
);

-- Should audit the gallery removal for the actor
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            created_at,
            details,
            event_id,
            group_id,
            resource_id,
            resource_type
        from audit_log
    $$,
    format(
        $$ values (
            'badge_artwork_deleted',
            %L::uuid,
            'delete-badge-artwork-actor',
            %L::uuid,
            current_timestamp,
            '{"file_name":"free.png"}'::jsonb,
            null::uuid,
            %L::uuid,
            %L::uuid,
            'badge_artwork'
        ) $$,
        :'actorID', :'communityID', :'groupID', :'artworkFreeID'
    ),
    'Should audit the gallery removal for the actor'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
