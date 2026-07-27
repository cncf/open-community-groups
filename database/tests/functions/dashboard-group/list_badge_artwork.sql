-- Tests group badge artwork gallery listings.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set artworkOneID 'b1040000-0000-0000-0000-000000000004'
\set artworkTwoID 'b1040000-0000-0000-0000-000000000005'
\set communityID 'b1040000-0000-0000-0000-000000000001'
\set groupCategoryID 'b1040000-0000-0000-0000-000000000002'
\set groupID 'b1040000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns the gallery
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Gallery Community', '/logo', 'gallery-community');

-- Category used by the gallery group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the gallery
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Gallery Group', 'gallery-group');

-- Reusable gallery artwork
insert into badge_artwork (badge_artwork_id, created_at, file_name, group_id)
values
    (:'artworkOneID', '2026-01-01 00:00:00+00', 'one.png', :'groupID'),
    (:'artworkTwoID', '2026-01-02 00:00:00+00', 'two.png', :'groupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list group-owned artwork
select is(
    list_badge_artwork(:'groupID')::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'badge_artwork_id', :'artworkTwoID'::uuid,
            'file_name', 'two.png'
        ),
        jsonb_build_object(
            'badge_artwork_id', :'artworkOneID'::uuid,
            'file_name', 'one.png'
        )
    ),
    'Should list group-owned artwork'
);

-- Should return an empty gallery for another group identifier
select is(list_badge_artwork(gen_random_uuid())::jsonb, '[]'::jsonb, 'Should return an empty gallery for another group identifier');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
