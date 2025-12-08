-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '10000000-0000-0000-0000-000000000001'
\set groupID     '10000000-0000-0000-0000-000000000002'

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
    'cloud-native-nyc',
    'Cloud Native NYC',
    'nyc.cloudnative.org',
    'Cloud Native NYC Community',
    'Community for cloud native technologies in NYC',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category (required by group)
insert into group_category (group_category_id, name, community_id)
values ('10000000-0000-0000-0000-000000000010', 'Tech', :'communityID');

-- Group
insert into "group" (group_id, community_id, name, slug, group_category_id)
values (:'groupID', :'communityID', 'Group NYC', 'group-nyc', '10000000-0000-0000-0000-000000000010');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return created sponsor
select is(
    (
        select (get_group_sponsor(
            add_group_sponsor(:'groupID'::uuid, '{
                "name":"Epsilon",
                "logo_url":"https://ex.com/epsilon.png",
                "website_url":"https://epsi.io"
            }'::jsonb
            ),
            :'groupID'::uuid
        )::jsonb - 'group_sponsor_id')
    ),
    '{
        "logo_url":"https://ex.com/epsilon.png",
        "name":"Epsilon",
        "website_url":"https://epsi.io"
    }'::jsonb,
    'Should return created sponsor'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
