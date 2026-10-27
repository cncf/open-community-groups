-- Tests adding group sponsors and auditing the creation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '3a040000-0000-0000-0000-000000000004'
\set communityID '3a040000-0000-0000-0000-000000000001'
\set groupCategoryID '3a040000-0000-0000-0000-000000000002'
\set groupID '3a040000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Actor adding the sponsors
select fx_user(:'actorUserID', jsonb_build_object('username', 'add-group-sponsor-actor'));

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group receiving the sponsors
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Add a sponsor with an explicit non-featured flag
select add_group_sponsor(
    :'actorUserID'::uuid,
    :'groupID'::uuid,
    '{
        "featured": false,
        "logo_url": "https://ex.com/epsilon.png",
        "name": "Epsilon",
        "website_url": "https://epsi.io"
    }'::jsonb
) as "explicitSponsorID" \gset

-- Add a sponsor without a featured flag
select add_group_sponsor(
    :'actorUserID'::uuid,
    :'groupID'::uuid,
    '{
        "logo_url": "https://ex.com/zeta.png",
        "name": "Zeta"
    }'::jsonb
) as "defaultSponsorID" \gset

-- Add a sponsor with an empty website_url
select add_group_sponsor(
    :'actorUserID'::uuid,
    :'groupID'::uuid,
    '{
        "logo_url": "https://ex.com/eta.png",
        "name": "Eta",
        "website_url": ""
    }'::jsonb
) as "emptyWebsiteSponsorID" \gset

-- Should create the expected audit row
select results_eq(
    format(
        $$
            select
                action,
                actor_user_id,
                actor_username,
                community_id,
                group_id,
                resource_id,
                resource_type
            from audit_log
            where resource_id = %L::uuid
        $$,
        :'explicitSponsorID'
    ),
    format(
        $$
            values (
                'group_sponsor_added',
                %L::uuid,
                'add-group-sponsor-actor',
                %L::uuid,
                %L::uuid,
                %L::uuid,
                'group_sponsor'
            )
        $$,
        :'actorUserID',
        :'communityID',
        :'groupID',
        :'explicitSponsorID'
    ),
    'Should create the expected audit row'
);

-- Should default featured to true when omitted
select results_eq(
    format(
        $$
            select featured, group_id, logo_url, name, website_url
            from group_sponsor
            where group_sponsor_id = %L::uuid
        $$,
        :'defaultSponsorID'
    ),
    format(
        $$
            values (true, %L::uuid, 'https://ex.com/zeta.png', 'Zeta', null::text)
        $$,
        :'groupID'
    ),
    'Should default featured to true when omitted'
);

-- Should persist the submitted sponsor fields
select results_eq(
    format(
        $$
            select featured, group_id, logo_url, name, website_url
            from group_sponsor
            where group_sponsor_id = %L::uuid
        $$,
        :'explicitSponsorID'
    ),
    format(
        $$
            values (false, %L::uuid, 'https://ex.com/epsilon.png', 'Epsilon', 'https://epsi.io')
        $$,
        :'groupID'
    ),
    'Should persist the submitted sponsor fields'
);

-- Should store an empty website_url as null
select results_eq(
    format(
        $$
            select featured, group_id, logo_url, name, website_url
            from group_sponsor
            where group_sponsor_id = %L::uuid
        $$,
        :'emptyWebsiteSponsorID'
    ),
    format(
        $$
            values (true, %L::uuid, 'https://ex.com/eta.png', 'Eta', null::text)
        $$,
        :'groupID'
    ),
    'Should store an empty website_url as null'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
