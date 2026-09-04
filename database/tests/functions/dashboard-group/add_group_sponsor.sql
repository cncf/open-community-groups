-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a040000-0000-0000-0000-000000000001'
\set groupCategoryID '3a040000-0000-0000-0000-000000000002'
\set groupID '3a040000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

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
        :'communityID', :'groupID'
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
