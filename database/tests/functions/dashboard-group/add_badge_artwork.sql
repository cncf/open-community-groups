-- Tests adding artwork to a group badge gallery.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

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
select fx_user(:'actorID', jsonb_build_object('username', 'add-badge-artwork-actor'));
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

-- Should persist the normalized gallery entry
select results_eq(
    $$ select file_name, group_id from badge_artwork $$,
    format($$ values ('art.png', %L::uuid) $$, :'groupID'),
    'Should persist the normalized gallery entry'
);

-- Should audit the gallery addition for the actor
select results_eq(
    $$
        select
            al.action,
            al.actor_user_id,
            al.actor_username,
            al.community_id,
            al.created_at,
            al.details,
            al.event_id,
            al.group_id,
            al.resource_type
        from audit_log al
        join badge_artwork ba on ba.badge_artwork_id = al.resource_id
    $$,
    format(
        $$ values (
            'badge_artwork_added',
            %L::uuid,
            'add-badge-artwork-actor',
            %L::uuid,
            current_timestamp,
            '{"file_name":"art.png"}'::jsonb,
            null::uuid,
            %L::uuid,
            'badge_artwork'
        ) $$,
        :'actorID', :'communityID', :'groupID'
    ),
    'Should audit the gallery addition for the actor'
);

-- Should accept duplicate artwork as an idempotent request
select lives_ok(
    format(
        $$select add_badge_artwork(%L::uuid, %L::uuid, %L::uuid, 'art.png')$$,
        :'actorID', :'communityID', :'groupID'
    ),
    'Should accept duplicate artwork as an idempotent request'
);

-- Should keep a single gallery entry for duplicate artwork
select is(
    (select count(*)::integer from badge_artwork),
    1,
    'Should keep a single gallery entry for duplicate artwork'
);

-- Should not audit duplicate artwork as another mutation
select is(
    (select count(*)::integer from audit_log),
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
