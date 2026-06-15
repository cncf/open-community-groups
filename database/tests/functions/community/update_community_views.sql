-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '0d060000-0000-0000-0000-000000000001'
\set inactiveCommunityID '0d060000-0000-0000-0000-000000000002'
\set unknownCommunityID '0d060000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    active,
    banner_mobile_url,
    banner_url,
    logo_url
) values
    (
        :'activeCommunityID',
        'update-community-views',
        'Update Community Views',
        'Community for update community views tests',
        true,
        'https://example.com/update-community-views-banner-mobile.png',
        'https://example.com/update-community-views-banner.png',
        'https://example.com/update-community-views-logo.png'
    ),
    (
        :'inactiveCommunityID',
        'inactive-update-community-views',
        'Inactive Update Community Views',
        'Inactive community for update community views tests',
        false,
        'https://example.com/inactive-update-community-views-banner-mobile.png',
        'https://example.com/inactive-update-community-views-banner.png',
        'https://example.com/inactive-update-community-views-logo.png'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should insert counters only for active communities
select lives_ok(
    format(
        $$select update_community_views(
            jsonb_build_array(
                jsonb_build_array(%L, current_date::text, 3),
                jsonb_build_array(%L, current_date::text, 5),
                jsonb_build_array(%L, current_date::text, 8)
            )
        )$$,
        :'activeCommunityID',
        :'inactiveCommunityID',
        :'unknownCommunityID'
    ),
    'Should accept counters only for active communities'
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

-- Should increment existing counters on conflict
select lives_ok(
    format(
        $$select update_community_views(
            jsonb_build_array(
                jsonb_build_array(%L, current_date::text, 4)
            )
        )$$,
        :'activeCommunityID'
    ),
    'Should accept additional counters for existing communities'
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

-- Should aggregate duplicate entries for the same community and day
select lives_ok(
    format(
        $$select update_community_views(
            jsonb_build_array(
                jsonb_build_array(%L, current_date::text, 1),
                jsonb_build_array(%L, current_date::text, 2)
            )
        )$$,
        :'activeCommunityID',
        :'activeCommunityID'
    ),
    'Should accept duplicate counters for the same community and day'
);

select is(
    (
        select total
        from community_views
        where community_id = :'activeCommunityID'
        and day = current_date
    ),
    10,
    'Should aggregate duplicate entries for the same community and day'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
