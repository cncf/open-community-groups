-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a110000-0000-0000-0000-000000000001'
\set groupCategoryID '3a110000-0000-0000-0000-000000000002'
\set groupID '3a110000-0000-0000-0000-000000000003'
\set sponsorID '3a110000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
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
    'cloud-native-berlin',
    'Cloud Native Berlin',
    'Community for cloud native technologies in Berlin',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Group Berlin', 'group-berlin');

-- Sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, featured, logo_url, website_url)
values (:'sponsorID', :'groupID', 'Theta', true, 'https://ex.com/theta.png', 'https://theta.io');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return sponsor when it belongs to group
select is(
    get_group_sponsor(:'sponsorID'::uuid, :'groupID'::uuid)::jsonb,
    jsonb_build_object(
        'featured', true,
        'group_sponsor_id', :'sponsorID'::uuid,
        'logo_url', 'https://ex.com/theta.png',
        'name', 'Theta',
        'website_url', 'https://theta.io'
    ),
    'Should return sponsor when it belongs to group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
