-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '30000000-0000-0000-0000-000000000001'
\set groupID     '30000000-0000-0000-0000-000000000002'
\set sponsorID   '30000000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'communityID',
    'cloud-native-paris',
    'Cloud Native Paris',
    'paris.cloudnative.org',
    'Cloud Native Paris Community',
    'Community for cloud native technologies in Paris',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category (required by group)
insert into group_category (group_category_id, name, community_id)
values ('30000000-0000-0000-0000-000000000010', 'Tech', :'communityID');

-- Group
insert into "group" (group_id, community_id, name, slug, group_category_id)
values (:'groupID', :'communityID', 'Group Paris', 'group-paris', '30000000-0000-0000-0000-000000000010');

-- Sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values (:'sponsorID', :'groupID', 'Iota', 'https://ex.com/iota.png', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: update_group_sponsor updates provided fields
select lives_ok(
    $$select update_group_sponsor('30000000-0000-0000-0000-000000000002'::uuid, '30000000-0000-0000-0000-000000000003'::uuid, '{
        "name":"Iota Updated",
        "level":"Gold",
        "logo_url":"https://ex.com/iota2.png",
        "website_url":"https://iota.io"
    }'::jsonb)$$,
    'update_group_sponsor should not error'
);

select results_eq(
    $$select name, logo_url, website_url from group_sponsor where group_sponsor_id = '30000000-0000-0000-0000-000000000003'::uuid$$,
    $$values ('Iota Updated'::text, 'https://ex.com/iota2.png'::text, 'https://iota.io'::text)$$,
    'update_group_sponsor should update fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
