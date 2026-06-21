-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '20000000-0000-0000-0000-000000000001'
\set groupID     '20000000-0000-0000-0000-000000000002'
\set sponsorID   '20000000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'allianceID',
    'cloud-native-berlin',
    'Cloud Native Berlin',
    'Alliance for cloud native technologies in Berlin',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group Category (required by group)
insert into group_category (group_category_id, name, alliance_id)
values ('20000000-0000-0000-0000-000000000010', 'Tech', :'allianceID');

-- Group
insert into "group" (group_id, alliance_id, name, slug, group_category_id)
values (:'groupID', :'allianceID', 'Group Berlin', 'group-berlin', '20000000-0000-0000-0000-000000000010');

-- Sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url, featured)
values (:'sponsorID', :'groupID', 'Theta', 'https://ex.com/theta.png', 'https://theta.io', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return sponsor when it belongs to group
select is(
    get_group_sponsor(:'sponsorID'::uuid, :'groupID'::uuid)::jsonb,
    '{
        "featured": true,
        "group_sponsor_id": "20000000-0000-0000-0000-000000000003",
        "logo_url":"https://ex.com/theta.png",
        "name":"Theta",
        "website_url":"https://theta.io"
    }'::jsonb,
    'Should return sponsor when it belongs to group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
