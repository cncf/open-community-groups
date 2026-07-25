-- Tests adding artwork to a group badge gallery.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'b1010000-0000-0000-0000-000000000001'
\set communityID 'b1010000-0000-0000-0000-000000000002'
\set groupCategoryID 'b1010000-0000-0000-0000-000000000003'
\set groupID 'b1010000-0000-0000-0000-000000000004'
\set viewerID 'b1010000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Admin authorized to manage badges
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'actorID', 'hash', 'art-admin@example.test', true, 'art-admin');

-- Viewer without badge write permission
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'viewerID', 'hash', 'art-viewer@example.test', true, 'art-viewer');

-- Community that owns the gallery
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Artwork Community', '/logo', 'artwork-community');

-- Category used by the gallery group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the gallery
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Artwork Group', 'artwork-group');

-- Authorized and read-only group team members
insert into group_team (group_id, accepted, role, user_id)
values
    (:'groupID', true, 'admin', :'actorID'),
    (:'groupID', true, 'viewer', :'viewerID');

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
    'badge artwork file name is invalid',
    'Should reject artwork path traversal'
);

-- Should reject a viewer before mutation
select throws_ok(
    format(
        $$select add_badge_artwork(%L::uuid, %L::uuid, %L::uuid, 'denied.png')$$,
        :'viewerID', :'communityID', :'groupID'
    ),
    '42501',
    'badge permission denied',
    'Should reject a viewer before mutation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
