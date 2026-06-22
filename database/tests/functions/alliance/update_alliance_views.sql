-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeAllianceID '0d060000-0000-0000-0000-000000000001'
\set inactiveAllianceID '0d060000-0000-0000-0000-000000000002'
\set unknownAllianceID '0d060000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    active,
    banner_mobile_url,
    banner_url,
    logo_url
) values
    (
        :'activeAllianceID',
        'update-alliance-views',
        'Update Alliance Views',
        'Alliance for update alliance views tests',
        true,
        'https://example.com/update-alliance-views-banner-mobile.png',
        'https://example.com/update-alliance-views-banner.png',
        'https://example.com/update-alliance-views-logo.png'
    ),
    (
        :'inactiveAllianceID',
        'inactive-update-alliance-views',
        'Inactive Update Alliance Views',
        'Inactive alliance for update alliance views tests',
        false,
        'https://example.com/inactive-update-alliance-views-banner-mobile.png',
        'https://example.com/inactive-update-alliance-views-banner.png',
        'https://example.com/inactive-update-alliance-views-logo.png'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should insert counters only for active alliances
select lives_ok(
    format(
        $$select update_alliance_views(
            jsonb_build_array(
                jsonb_build_array(%L, current_date::text, 3),
                jsonb_build_array(%L, current_date::text, 5),
                jsonb_build_array(%L, current_date::text, 8)
            )
        )$$,
        :'activeAllianceID',
        :'inactiveAllianceID',
        :'unknownAllianceID'
    ),
    'Should accept counters only for active alliances'
);

select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'alliance_id', alliance_id::text,
                'day', day::text,
                'total', total
            )
            order by day, alliance_id
        )
        from alliance_views
    ),
    jsonb_build_array(
        jsonb_build_object(
            'alliance_id', :'activeAllianceID',
            'day', current_date::text,
            'total', 3
        )
    ),
    'Should insert counters only for active alliances'
);

-- Should increment existing counters on conflict
select lives_ok(
    format(
        $$select update_alliance_views(
            jsonb_build_array(
                jsonb_build_array(%L, current_date::text, 4)
            )
        )$$,
        :'activeAllianceID'
    ),
    'Should accept additional counters for existing alliances'
);

select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'alliance_id', alliance_id::text,
                'day', day::text,
                'total', total
            )
            order by day, alliance_id
        )
        from alliance_views
    ),
    jsonb_build_array(
        jsonb_build_object(
            'alliance_id', :'activeAllianceID',
            'day', current_date::text,
            'total', 7
        )
    ),
    'Should increment existing counters on conflict'
);

-- Should aggregate duplicate entries for the same alliance and day
select lives_ok(
    format(
        $$select update_alliance_views(
            jsonb_build_array(
                jsonb_build_array(%L, current_date::text, 1),
                jsonb_build_array(%L, current_date::text, 2)
            )
        )$$,
        :'activeAllianceID',
        :'activeAllianceID'
    ),
    'Should accept duplicate counters for the same alliance and day'
);

select is(
    (
        select total
        from alliance_views
        where alliance_id = :'activeAllianceID'
        and day = current_date
    ),
    10,
    'Should aggregate duplicate entries for the same alliance and day'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
