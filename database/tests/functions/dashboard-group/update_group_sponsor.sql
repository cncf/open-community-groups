-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a3d0000-0000-0000-0000-000000000001'
\set groupCategoryID '3a3d0000-0000-0000-0000-000000000002'
\set groupID '3a3d0000-0000-0000-0000-000000000003'
\set sponsorID '3a3d0000-0000-0000-0000-000000000004'
\set wrongGroupID '3a3d0000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'wrongGroupID', :'communityID', :'groupCategoryID');

-- Sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url, featured)
values (:'sponsorID', :'groupID', 'Iota', 'https://ex.com/iota.png', null, false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update provided fields
select lives_ok(
    format(
        $$select update_group_sponsor(null::uuid, %L::uuid, %L::uuid, '{
            "featured": true,
            "name":"Iota Updated",
            "level":"Gold",
            "logo_url":"https://ex.com/iota2.png",
            "website_url":"https://iota.io"
        }'::jsonb)$$,
        :'groupID', :'sponsorID'
    ),
    'Should execute update with all sponsor fields provided'
);

select results_eq(
    format(
        $$select featured, name, logo_url, website_url from group_sponsor where group_sponsor_id = %L::uuid$$,
        :'sponsorID'
    ),
    $$values (true, 'Iota Updated'::text, 'https://ex.com/iota2.png'::text, 'https://iota.io'::text)$$,
    'Should update fields'
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
        values (
            'group_sponsor_updated',
            null::uuid,
            null::text,
            %L::uuid,
            %L::uuid,
            'group_sponsor',
            %L::uuid
        )
        $$,
        :'communityID', :'groupID', :'sponsorID'
    ),
    'Should create the expected audit row'
);

-- Should set website_url to null when field not provided
select lives_ok(
    format(
        $$select update_group_sponsor(
            null::uuid,
            %L::uuid,
            %L::uuid,
            '{
                "featured": false,
                "name": "Iota Final",
                "logo_url": "https://ex.com/iota3.png"
            }'::jsonb
        )$$,
        :'groupID', :'sponsorID'
    ),
    'Should execute update without website_url field'
);

-- Should set website_url to null when ommitted from payload
select results_eq(
    format(
        $$select featured, name, logo_url, website_url from group_sponsor where group_sponsor_id = %L::uuid$$,
        :'sponsorID'
    ),
    $$values (false, 'Iota Final'::text, 'https://ex.com/iota3.png'::text, null::text)$$,
    'Should set website_url to null when omitted from payload'
);

-- Should silently ignore updates for a sponsor outside the selected group
select lives_ok(
    format(
        $$select update_group_sponsor(
            null::uuid,
            %L::uuid,
            %L::uuid,
            '{
                "featured": true,
                "name": "Wrong Group",
                "logo_url": "https://ex.com/wrong.png",
                "website_url": "https://wrong.example.com"
            }'::jsonb
        )$$,
        :'wrongGroupID', :'sponsorID'
    ),
    'Should accept updates for a sponsor outside the selected group without error'
);

select results_eq(
    format(
        $$select featured, name, logo_url, website_url from group_sponsor where group_sponsor_id = %L::uuid$$,
        :'sponsorID'
    ),
    $$values (false, 'Iota Final'::text, 'https://ex.com/iota3.png'::text, null::text)$$,
    'Should leave sponsor fields unchanged when sponsor belongs to another group'
);

select results_eq(
    $$select count(*) from audit_log$$,
    $$values (2::bigint)$$,
    'Should not create an audit row when sponsor belongs to another group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
