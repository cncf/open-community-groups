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

-- Baseline community, categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');


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
