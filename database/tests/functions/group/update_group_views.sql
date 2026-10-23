-- Tests recording daily group view counters.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeGroupID '6a070000-0000-0000-0000-000000000001'
\set communityID '6a070000-0000-0000-0000-000000000002'
\set conflictGroupID '6a070000-0000-0000-0000-000000000006'
\set duplicateGroupID '6a070000-0000-0000-0000-000000000007'
\set groupCategoryID '6a070000-0000-0000-0000-000000000003'
\set inactiveGroupID '6a070000-0000-0000-0000-000000000004'
\set unknownGroupID '6a070000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and group category
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group receiving its first counter
select fx_group(:'activeGroupID', :'communityID', :'groupCategoryID');

-- Active group with an existing counter for today
select fx_group(:'conflictGroupID', :'communityID', :'groupCategoryID');

-- Active group receiving duplicate entries in one batch
select fx_group(:'duplicateGroupID', :'communityID', :'groupCategoryID');

-- Inactive group ignored by view counters
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Existing counter incremented by the conflict scenario
insert into group_views (group_id, day, total)
values (:'conflictGroupID', current_date, 3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should aggregate duplicate entries for the same group and day
select lives_ok(
    format(
        $$
        select update_group_views(
            jsonb_build_array(
                jsonb_build_array(%L::text, current_date::text, 1),
                jsonb_build_array(%L::text, current_date::text, 2)
            )
        )
        $$,
        :'duplicateGroupID', :'duplicateGroupID'
    ),
    'Should record duplicate view entries without error'
);
select is(
    (
        select total
        from group_views
        where group_id = :'duplicateGroupID'
        and day = current_date
    ),
    3,
    'Should aggregate duplicate entries for the same group and day'
);

-- Should increment existing counters on conflict
select lives_ok(
    format(
        $$
        select update_group_views(
            jsonb_build_array(
                jsonb_build_array(%L::text, current_date::text, 4)
            )
        )
        $$,
        :'conflictGroupID'
    ),
    'Should record additional views for an existing counter without error'
);
select is(
    (
        select total
        from group_views
        where group_id = :'conflictGroupID'
        and day = current_date
    ),
    7,
    'Should increment existing counters on conflict'
);

-- Should insert counters only for active groups
select lives_ok(
    format(
        $$
        select update_group_views(
            jsonb_build_array(
                jsonb_build_array(%L::text, current_date::text, 3),
                jsonb_build_array(%L::text, current_date::text, 5),
                jsonb_build_array(%L::text, current_date::text, 8)
            )
        )
        $$,
        :'activeGroupID', :'inactiveGroupID', :'unknownGroupID'
    ),
    'Should record views for active, inactive and unknown groups without error'
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
        where group_id in (
            :'activeGroupID',
            :'inactiveGroupID',
            :'unknownGroupID'
        )
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
