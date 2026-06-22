-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a040000-0000-0000-0000-000000000001'
\set groupCategoryID '3a040000-0000-0000-0000-000000000002'
\set groupID '3a040000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'cloud-native-nyc',
    'Cloud Native NYC',
    'Alliance for cloud native technologies in NYC',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Tech');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Group NYC', 'group-nyc');

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
            alliance_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        select
            'group_sponsor_added',
            null::uuid,
            null::text,
            %L::uuid,
            %L::uuid,
            'group_sponsor',
            group_sponsor_id
        from group_sponsor
        where name = 'Epsilon'
        $$,
        :'allianceID', :'groupID'
    ),
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
