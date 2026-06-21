-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeAllianceID '00000000-0000-0000-0000-000000000301'
\set inactiveAllianceID '00000000-0000-0000-0000-000000000302'
\set unknownAllianceID '00000000-0000-0000-0000-999999999999'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliances
insert into alliance (
    alliance_id,
    active,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (:'activeAllianceID', true, 'active-alliance', 'Active Alliance', 'Alliance for update_alliance_views tests', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png'),
    (:'inactiveAllianceID', false, 'inactive-alliance', 'Inactive Alliance', 'Inactive alliance', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should insert counters only for active alliances
select update_alliance_views(
    jsonb_build_array(
        jsonb_build_array(:'activeAllianceID'::text, current_date::text, 3),
        jsonb_build_array(:'inactiveAllianceID'::text, current_date::text, 5),
        jsonb_build_array(:'unknownAllianceID'::text, current_date::text, 8)
    )
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

-- Should ignore counters for inactive or unknown alliances
select is(
    (select count(*) from alliance_views),
    1::bigint,
    'Should ignore counters for inactive or unknown alliances'
);

-- Should increment existing counters on conflict
select update_alliance_views(
    jsonb_build_array(
        jsonb_build_array(:'activeAllianceID'::text, current_date::text, 4)
    )
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
select update_alliance_views(
    jsonb_build_array(
        jsonb_build_array(:'activeAllianceID'::text, current_date::text, 1),
        jsonb_build_array(:'activeAllianceID'::text, current_date::text, 2)
    )
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
