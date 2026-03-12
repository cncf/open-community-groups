-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '00000000-0000-0000-0000-000000000301'
\set inactiveCommunityID '00000000-0000-0000-0000-000000000302'
\set unknownCommunityID '00000000-0000-0000-0000-999999999999'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    active,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (:'activeCommunityID', true, 'active-community', 'Active Community', 'Community for update_community_views tests', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png'),
    (:'inactiveCommunityID', false, 'inactive-community', 'Inactive Community', 'Inactive community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should insert counters only for active communities
select update_community_views(
    jsonb_build_array(
        jsonb_build_array(:'activeCommunityID'::text, current_date::text, 3),
        jsonb_build_array(:'inactiveCommunityID'::text, current_date::text, 5),
        jsonb_build_array(:'unknownCommunityID'::text, current_date::text, 8)
    )
);

select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'community_id', community_id::text,
                'day', day::text,
                'total', total
            )
            order by day, community_id
        )
        from community_views
    ),
    jsonb_build_array(
        jsonb_build_object(
            'community_id', :'activeCommunityID',
            'day', current_date::text,
            'total', 3
        )
    ),
    'Should insert counters only for active communities'
);

-- Should ignore counters for inactive or unknown communities
select is(
    (select count(*) from community_views),
    1::bigint,
    'Should ignore counters for inactive or unknown communities'
);

-- Should increment existing counters on conflict
select update_community_views(
    jsonb_build_array(
        jsonb_build_array(:'activeCommunityID'::text, current_date::text, 4)
    )
);

select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'community_id', community_id::text,
                'day', day::text,
                'total', total
            )
            order by day, community_id
        )
        from community_views
    ),
    jsonb_build_array(
        jsonb_build_object(
            'community_id', :'activeCommunityID',
            'day', current_date::text,
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
