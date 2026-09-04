-- Tests adding artwork to a group badge gallery.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'b1010000-0000-0000-0000-000000000001'
\set communityID 'b1010000-0000-0000-0000-000000000002'
\set groupCategoryID 'b1010000-0000-0000-0000-000000000003'
\set groupID 'b1010000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'actorID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should add normalized artwork
select lives_ok(
    format(
        $$select add_badge_artwork(%L::uuid, %L::uuid, %L::uuid, '/images/badges/art.png')$$,
        :'actorID', :'communityID', :'groupID'
    ),
    'Should add normalized artwork'
);

-- Should persist the gallery entry and audit row
select ok(
    exists (select 1 from badge_artwork where file_name = 'art.png')
    and exists (
        select 1 from audit_log
        where action = 'badge_artwork_added'
        and details = '{"file_name":"art.png"}'::jsonb
    ),
    'Should persist the gallery entry and audit row'
);

-- Should accept duplicate artwork as an idempotent request
select lives_ok(
    format(
        $$select add_badge_artwork(%L::uuid, %L::uuid, %L::uuid, 'art.png')$$,
        :'actorID', :'communityID', :'groupID'
    ),
    'Should accept duplicate artwork as an idempotent request'
);

-- Should not audit duplicate artwork as another mutation
select is(
    (select count(*)::integer from audit_log where action = 'badge_artwork_added'),
    1,
    'Should not audit duplicate artwork as another mutation'
);

-- Should reject artwork path traversal
select throws_ok(
    format(
        $$select add_badge_artwork(%L::uuid, %L::uuid, %L::uuid, '../../log-out')$$,
        :'actorID', :'communityID', :'groupID'
    ),
    'OCG01',
    'badge artwork file name is invalid',
    'Should reject artwork path traversal'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
