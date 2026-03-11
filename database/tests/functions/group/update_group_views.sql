-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set inactiveGroupID '00000000-0000-0000-0000-000000000302'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupCategoryID '00000000-0000-0000-0000-000000000201'
\set activeGroupID '00000000-0000-0000-0000-000000000301'
\set unknownGroupID '00000000-0000-0000-0000-999999999999'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community and group category
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
    'views-community',
    'Views Community',
    'Community for update_group_views tests',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values
    (:'activeGroupID', :'communityID', :'groupCategoryID', 'Active Group', 'active-group', true, false),
    (:'inactiveGroupID', :'communityID', :'groupCategoryID', 'Inactive Group', 'inactive-group', false, false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should insert counters only for active groups
select update_group_views(
    jsonb_build_array(
        jsonb_build_array(:'activeGroupID'::text, current_date::text, 3),
        jsonb_build_array(:'inactiveGroupID'::text, current_date::text, 5),
        jsonb_build_array(:'unknownGroupID'::text, current_date::text, 8)
    )
);

select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'day', day::text,
                'group_id', group_id::text,
                'total', total
            )
            order by day, group_id
        )
        from group_views
    ),
    jsonb_build_array(
        jsonb_build_object(
            'day', current_date::text,
            'group_id', :'activeGroupID',
            'total', 3
        )
    ),
    'Should insert counters only for active groups'
);

-- Should ignore counters for inactive or unknown groups
select is(
    (select count(*) from group_views),
    1::bigint,
    'Should ignore counters for inactive or unknown groups'
);

-- Should increment existing counters on conflict
select update_group_views(
    jsonb_build_array(
        jsonb_build_array(:'activeGroupID'::text, current_date::text, 4)
    )
);

select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'day', day::text,
                'group_id', group_id::text,
                'total', total
            )
            order by day, group_id
        )
        from group_views
    ),
    jsonb_build_array(
        jsonb_build_object(
            'day', current_date::text,
            'group_id', :'activeGroupID',
            'total', 7
        )
    ),
    'Should increment existing counters on conflict'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
