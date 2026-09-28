-- Tests get_group_upcoming_events includes approved co-hosted events and de-duplicates before limit.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostedEarlyEventID 'e5270000-0000-0000-0000-000000000001'
\set communityID 'e5270000-0000-0000-0000-000000000002'
\set duplicateEventID 'e5270000-0000-0000-0000-000000000003'
\set eventCategoryID 'e5270000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5270000-0000-0000-0000-000000000005'
\set ownedLateEventID 'e5270000-0000-0000-0000-000000000006'
\set ownerGroupID 'e5270000-0000-0000-0000-000000000007'
\set subgroupID 'e5270000-0000-0000-0000-000000000008'
\set targetGroupID 'e5270000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and groups
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'ownerGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'targetGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('slug', 'upcoming-target'));
select fx_group(:'subgroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'targetGroupID'));

-- Upcoming owned, subgroup-owned, and co-hosted events
select fx_event(:'cohostedEarlyEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '1 day'));
select fx_event(:'duplicateEventID', :'subgroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '2 days'));
select fx_event(:'ownedLateEventID', :'targetGroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '3 days'));

-- Approved co-host credits
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    (current_timestamp, 'approved', :'cohostedEarlyEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'duplicateEventID', :'targetGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should include approved co-hosted events before owned later events
select is(
    get_group_upcoming_events(:'communityID'::uuid, 'upcoming-target', array['in-person']::text[], 10)::jsonb->0->>'event_id',
    :'cohostedEarlyEventID',
    'Should include approved co-hosted events before owned later events'
);

-- Should de-duplicate before limiting
select is(
    jsonb_array_length(get_group_upcoming_events(:'communityID'::uuid, 'upcoming-target', array['in-person']::text[], 2)::jsonb),
    2,
    'Should de-duplicate before limiting'
);

-- Should return the duplicated subgroup/co-hosted event only once
select is(
    (
        select count(*)::int
        from jsonb_array_elements(get_group_upcoming_events(:'communityID'::uuid, 'upcoming-target', array['in-person']::text[], 10)::jsonb) item
        where item->>'event_id' = :'duplicateEventID'
    ),
    1,
    'Should return the duplicated subgroup/co-hosted event only once'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
