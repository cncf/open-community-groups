-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

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
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'cloud-native-nyc',
    'Cloud Native NYC',
    'Community for cloud native technologies in NYC',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
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
            add_group_sponsor(null::uuid, :'groupID'::uuid, '{
                "featured": true,
                "name":"Epsilon",
                "logo_url":"https://ex.com/epsilon.png",
                "website_url":"https://epsi.io"
            }'::jsonb
            ),
            :'groupID'::uuid
        )::jsonb - 'group_sponsor_id')
    ),
    '{
        "featured": true,
        "logo_url":"https://ex.com/epsilon.png",
        "name":"Epsilon",
        "website_url":"https://epsi.io"
    }'::jsonb,
    'Should return created sponsor'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    $$
        select
            'group_sponsor_added',
            null::uuid,
            null::text,
            '10000000-0000-0000-0000-000000000001'::uuid,
            '10000000-0000-0000-0000-000000000002'::uuid,
            'group_sponsor',
            group_sponsor_id
        from group_sponsor
        where name = 'Epsilon'
    $$,
    'Should create the expected audit row'
);

-- Should default featured to true when omitted
select is(
    (
        select (get_group_sponsor(
            add_group_sponsor(null::uuid, :'groupID'::uuid, '{
                "name":"Zeta",
                "logo_url":"https://ex.com/zeta.png"
            }'::jsonb
            ),
            :'groupID'::uuid
        )::jsonb - 'group_sponsor_id')
    ),
    '{
        "featured": true,
        "logo_url":"https://ex.com/zeta.png",
        "name":"Zeta"
    }'::jsonb,
    'Should default featured to true when omitted'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
