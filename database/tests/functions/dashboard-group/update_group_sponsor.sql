-- Tests updating group sponsors.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '3a3d0000-0000-0000-0000-000000000001'
\set communityID '3a3d0000-0000-0000-0000-000000000002'
\set groupCategoryID '3a3d0000-0000-0000-0000-000000000003'
\set groupID '3a3d0000-0000-0000-0000-000000000004'
\set sponsorEmptyWebsiteID '3a3d0000-0000-0000-0000-000000000005'
\set sponsorFeaturedOmittedID '3a3d0000-0000-0000-0000-000000000006'
\set sponsorID '3a3d0000-0000-0000-0000-000000000007'
\set sponsorWebsiteOmittedID '3a3d0000-0000-0000-0000-000000000008'
\set sponsorWrongGroupID '3a3d0000-0000-0000-0000-000000000009'
\set wrongGroupID '3a3d0000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group category and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'wrongGroupID', :'communityID', :'groupCategoryID');

-- Actor updating the sponsors
select fx_user(:'actorUserID', jsonb_build_object('username', 'update-group-sponsor-actor'));

-- Sponsor whose website is cleared with an empty string
insert into group_sponsor (featured, group_id, group_sponsor_id, logo_url, name, website_url)
values (false, :'groupID', :'sponsorEmptyWebsiteID', 'https://ex.com/kappa.png', 'Kappa', 'https://kappa.io');

-- Featured sponsor updated without a featured flag
insert into group_sponsor (featured, group_id, group_sponsor_id, logo_url, name, website_url)
values (true, :'groupID', :'sponsorFeaturedOmittedID', 'https://ex.com/eta.png', 'Eta', 'https://eta.io');

-- Sponsor updated with every field provided
insert into group_sponsor (featured, group_id, group_sponsor_id, logo_url, name, website_url)
values (false, :'groupID', :'sponsorID', 'https://ex.com/iota.png', 'Iota', null);

-- Sponsor whose website is cleared by omitting it
insert into group_sponsor (featured, group_id, group_sponsor_id, logo_url, name, website_url)
values (false, :'groupID', :'sponsorWebsiteOmittedID', 'https://ex.com/theta.png', 'Theta', 'https://theta.io');

-- Sponsor targeted through a group that does not own it
insert into group_sponsor (featured, group_id, group_sponsor_id, logo_url, name, website_url)
values (false, :'groupID', :'sponsorWrongGroupID', 'https://ex.com/lambda.png', 'Lambda', 'https://lambda.io');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update all provided fields
select lives_ok(
    format(
        $$select update_group_sponsor(%L::uuid, %L::uuid, %L::uuid, '{
            "featured": true,
            "logo_url": "https://ex.com/iota2.png",
            "name": "Iota Updated",
            "website_url": "https://iota.io"
        }'::jsonb)$$,
        :'actorUserID', :'groupID', :'sponsorID'
    ),
    'Should execute update with all sponsor fields provided'
);

select results_eq(
    format(
        $$select featured, logo_url, name, website_url from group_sponsor where group_sponsor_id = %L::uuid$$,
        :'sponsorID'
    ),
    $$values (true, 'https://ex.com/iota2.png'::text, 'Iota Updated'::text, 'https://iota.io'::text)$$,
    'Should update all provided fields'
);

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
            resource_type,
            resource_id
        from audit_log
        where resource_id = %L::uuid
        $$,
        :'sponsorID'
    ),
    format(
        $$
        values (
            'group_sponsor_updated',
            %L::uuid,
            'update-group-sponsor-actor',
            %L::uuid,
            %L::uuid,
            'group_sponsor',
            %L::uuid
        )
        $$,
        :'actorUserID', :'communityID', :'groupID', :'sponsorID'
    ),
    'Should create the expected audit row'
);

-- Should default featured to false when omitted from payload
select lives_ok(
    format(
        $$select update_group_sponsor(%L::uuid, %L::uuid, %L::uuid, '{
            "logo_url": "https://ex.com/eta.png",
            "name": "Eta",
            "website_url": "https://eta.io"
        }'::jsonb)$$,
        :'actorUserID', :'groupID', :'sponsorFeaturedOmittedID'
    ),
    'Should execute update without featured field'
);

select results_eq(
    format(
        $$select featured, logo_url, name, website_url from group_sponsor where group_sponsor_id = %L::uuid$$,
        :'sponsorFeaturedOmittedID'
    ),
    $$values (false, 'https://ex.com/eta.png'::text, 'Eta'::text, 'https://eta.io'::text)$$,
    'Should default featured to false when omitted from payload'
);

-- Should silently ignore updates for a sponsor outside the selected group
select lives_ok(
    format(
        $$select update_group_sponsor(%L::uuid, %L::uuid, %L::uuid, '{
            "featured": true,
            "logo_url": "https://ex.com/wrong.png",
            "name": "Wrong Group",
            "website_url": "https://wrong.example.com"
        }'::jsonb)$$,
        :'actorUserID', :'wrongGroupID', :'sponsorWrongGroupID'
    ),
    'Should accept updates for a sponsor outside the selected group without error'
);

select results_eq(
    format(
        $$select featured, logo_url, name, website_url from group_sponsor where group_sponsor_id = %L::uuid$$,
        :'sponsorWrongGroupID'
    ),
    $$values (false, 'https://ex.com/lambda.png'::text, 'Lambda'::text, 'https://lambda.io'::text)$$,
    'Should leave sponsor fields unchanged when sponsor belongs to another group'
);

select is(
    (select count(*) from audit_log where resource_id = :'sponsorWrongGroupID'::uuid),
    0::bigint,
    'Should not create an audit row when sponsor belongs to another group'
);

-- Should set website_url to null when empty in payload
select lives_ok(
    format(
        $$select update_group_sponsor(%L::uuid, %L::uuid, %L::uuid, '{
            "featured": false,
            "logo_url": "https://ex.com/kappa.png",
            "name": "Kappa",
            "website_url": ""
        }'::jsonb)$$,
        :'actorUserID', :'groupID', :'sponsorEmptyWebsiteID'
    ),
    'Should execute update with an empty website_url'
);

select results_eq(
    format(
        $$select featured, logo_url, name, website_url from group_sponsor where group_sponsor_id = %L::uuid$$,
        :'sponsorEmptyWebsiteID'
    ),
    $$values (false, 'https://ex.com/kappa.png'::text, 'Kappa'::text, null::text)$$,
    'Should set website_url to null when empty in payload'
);

-- Should set website_url to null when omitted from payload
select lives_ok(
    format(
        $$select update_group_sponsor(%L::uuid, %L::uuid, %L::uuid, '{
            "featured": false,
            "logo_url": "https://ex.com/theta2.png",
            "name": "Theta Final"
        }'::jsonb)$$,
        :'actorUserID', :'groupID', :'sponsorWebsiteOmittedID'
    ),
    'Should execute update without website_url field'
);

select results_eq(
    format(
        $$select featured, logo_url, name, website_url from group_sponsor where group_sponsor_id = %L::uuid$$,
        :'sponsorWebsiteOmittedID'
    ),
    $$values (false, 'https://ex.com/theta2.png'::text, 'Theta Final'::text, null::text)$$,
    'Should set website_url to null when omitted from payload'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
