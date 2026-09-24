-- Tests get_group_stats cohosted_events analytics.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledCohostedEventID 'e5290000-0000-0000-0000-000000000001'
\set cohostedEventID 'e5290000-0000-0000-0000-000000000002'
\set communityID 'e5290000-0000-0000-0000-000000000003'
\set eventCategoryID 'e5290000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5290000-0000-0000-0000-000000000005'
\set ownedEventID 'e5290000-0000-0000-0000-000000000006'
\set ownerGroupID 'e5290000-0000-0000-0000-000000000007'
\set subgroupCohostedEventID 'e5290000-0000-0000-0000-000000000008'
\set subgroupID 'e5290000-0000-0000-0000-000000000009'
\set subgroupOwnedEventID 'e5290000-0000-0000-0000-00000000000a'
\set targetGroupID 'e5290000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and events
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'ownerGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'targetGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'subgroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'targetGroupID'));
select fx_event(:'canceledCohostedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('canceled', true, 'published', true, 'starts_at', current_timestamp + interval '4 days'));
select fx_event(:'cohostedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '1 day'));
select fx_event(:'ownedEventID', :'targetGroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '2 days'));
select fx_event(:'subgroupCohostedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '3 days'));
select fx_event(:'subgroupOwnedEventID', :'subgroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '5 days'));

-- Co-host analytics rows
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    (current_timestamp, 'approved', :'canceledCohostedEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'cohostedEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'subgroupCohostedEventID', :'subgroupID'),
    (current_timestamp, 'approved', :'subgroupOwnedEventID', :'targetGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should count only approved co-hosted events outside the owner scope
select is(
    (get_group_stats(:'communityID'::uuid, :'targetGroupID'::uuid, false)::jsonb->'cohosted_events'->>'total')::int,
    2,
    'Should count only approved co-hosted events outside the owner scope'
);

-- Should respect the subgroup toggle for co-hosted events
select is(
    (get_group_stats(:'communityID'::uuid, :'targetGroupID'::uuid, true)::jsonb->'cohosted_events'->>'total')::int,
    2,
    'Should respect the subgroup toggle for co-hosted events'
);

-- Should exclude owned and subgroup-owned events from cohosted_events
select is(
    (get_group_stats(:'communityID'::uuid, :'targetGroupID'::uuid, true)::jsonb->'events'->>'total')::int,
    2,
    'Should exclude owned and subgroup-owned events from cohosted_events'
);

-- Should exclude canceled co-hosted events
select ok(
    not ((get_group_stats(:'communityID'::uuid, :'targetGroupID'::uuid, true)::jsonb->'cohosted_events'->'running_total')::text like '%' || :'canceledCohostedEventID' || '%'),
    'Should exclude canceled co-hosted events'
);

-- Should leave other domains unchanged by co-host rows
select is(
    (get_group_stats(:'communityID'::uuid, :'targetGroupID'::uuid, false)::jsonb->'attendees'->>'total')::int,
    0,
    'Should leave other domains unchanged by co-host rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
