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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'cloud-native-paris',
    'Cloud Native Paris',
    'Community for cloud native technologies in Paris',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Group Paris', 'group-paris'),
    (:'wrongGroupID', :'communityID', :'groupCategoryID', 'Group Lyon', 'group-lyon');

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
