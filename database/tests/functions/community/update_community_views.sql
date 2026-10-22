-- Tests recording daily community view counters.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '0d060000-0000-0000-0000-000000000001'
\set conflictCommunityID '0d060000-0000-0000-0000-000000000004'
\set duplicateCommunityID '0d060000-0000-0000-0000-000000000005'
\set inactiveCommunityID '0d060000-0000-0000-0000-000000000002'
\set unknownCommunityID '0d060000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community receiving its first counter
select fx_community(:'activeCommunityID');

-- Active community with an existing counter for today
select fx_community(:'conflictCommunityID');

-- Active community receiving duplicate entries in one batch
select fx_community(:'duplicateCommunityID');

-- Inactive community ignored by view counters
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

-- Existing counter incremented by the conflict scenario
insert into community_views (community_id, day, total)
values (:'conflictCommunityID', current_date, 3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should aggregate duplicate entries for the same community and day
select lives_ok(
    format(
        $$select update_community_views(
            jsonb_build_array(
                jsonb_build_array(%L, current_date::text, 1),
                jsonb_build_array(%L, current_date::text, 2)
            )
        )$$,
        :'duplicateCommunityID',
        :'duplicateCommunityID'
    ),
    'Should accept duplicate counters for the same community and day'
);
select is(
    (
        select total
        from community_views
        where community_id = :'duplicateCommunityID'
        and day = current_date
    ),
    3,
    'Should aggregate duplicate entries for the same community and day'
);

-- Should increment existing counters on conflict
select lives_ok(
    format(
        $$select update_community_views(
            jsonb_build_array(
                jsonb_build_array(%L, current_date::text, 4)
            )
        )$$,
        :'conflictCommunityID'
    ),
    'Should accept additional counters for existing communities'
);
select is(
    (
        select total
        from community_views
        where community_id = :'conflictCommunityID'
        and day = current_date
    ),
    7,
    'Should increment existing counters on conflict'
);

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
        where community_id in (
            :'activeCommunityID',
            :'inactiveCommunityID',
            :'unknownCommunityID'
        )
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
