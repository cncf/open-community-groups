-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '20000000-0000-0000-0000-000000000001'
\set groupID     '20000000-0000-0000-0000-000000000002'
\set sponsorID   '20000000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_url
) values (
    :'communityID',
    'cloud-native-berlin',
    'Cloud Native Berlin',
    'Community for cloud native technologies in Berlin',
    'https://example.com/logo.png',
    'https://example.com/banner.png'
);

-- Group Category (required by group)
insert into group_category (group_category_id, name, community_id)
values ('20000000-0000-0000-0000-000000000010', 'Tech', :'communityID');

-- Group
insert into "group" (group_id, community_id, name, slug, group_category_id)
values (:'groupID', :'communityID', 'Group Berlin', 'group-berlin', '20000000-0000-0000-0000-000000000010');

-- Sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values (:'sponsorID', :'groupID', 'Theta', 'https://ex.com/theta.png', 'https://theta.io');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return sponsor when it belongs to group
select is(
    get_group_sponsor(:'sponsorID'::uuid, :'groupID'::uuid)::jsonb,
    '{
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
