-- Tests list_group_page_events owner, subgroup, co-host, duplicate, and cross-community scope.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e5140000-0000-0000-0000-000000000001'
\set crossCommunityID 'e5140000-0000-0000-0000-000000000002'
\set crossEventCategoryID 'e5140000-0000-0000-0000-000000000003'
\set crossGroupCategoryID 'e5140000-0000-0000-0000-000000000004'
\set crossOwnerEventID 'e5140000-0000-0000-0000-000000000005'
\set crossOwnerGroupID 'e5140000-0000-0000-0000-000000000006'
\set eventCategoryID 'e5140000-0000-0000-0000-000000000007'
\set groupCategoryID 'e5140000-0000-0000-0000-000000000008'
\set inactiveOwnerEventID 'e5140000-0000-0000-0000-000000000009'
\set inactiveOwnerGroupID 'e5140000-0000-0000-0000-00000000000a'
\set otherCohostGroupID 'e5140000-0000-0000-0000-00000000000b'
\set ownedEventID 'e5140000-0000-0000-0000-00000000000c'
\set ownerEventID 'e5140000-0000-0000-0000-00000000000d'
\set ownerGroupID 'e5140000-0000-0000-0000-00000000000e'
\set pendingEventID 'e5140000-0000-0000-0000-00000000000f'
\set subgroupCohostEventID 'e5140000-0000-0000-0000-000000000010'
\set subgroupID 'e5140000-0000-0000-0000-000000000011'
\set subgroupOwnedEventID 'e5140000-0000-0000-0000-000000000012'
\set targetGroupID 'e5140000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and categories
select fx_community(:'communityID');
select fx_community(:'crossCommunityID');
select fx_event_category(:'crossEventCategoryID', :'crossCommunityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'crossGroupCategoryID', :'crossCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Target group, subgroup, and event owners
select fx_group(:'crossOwnerGroupID', :'crossCommunityID', :'crossGroupCategoryID');
select fx_group(:'inactiveOwnerGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));
select fx_group(:'otherCohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'ownerGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'targetGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('slug', 'target-page'));
select fx_group(:'subgroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'targetGroupID'));

-- Owned, subgroup-owned, co-hosted, pending, inactive-owner, and cross-community events
select fx_event(:'crossOwnerEventID', :'crossOwnerGroupID', :'crossEventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '6 days'));
select fx_event(:'inactiveOwnerEventID', :'inactiveOwnerGroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '5 days'));
select fx_event(:'ownedEventID', :'targetGroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '1 day'));
select fx_event(:'ownerEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '3 days'));
select fx_event(:'pendingEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '4 days'));
select fx_event(:'subgroupCohostEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '7 days'));
select fx_event(:'subgroupOwnedEventID', :'subgroupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '2 days'));

-- Co-host rows covering the group-page scope
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    (current_timestamp, 'approved', :'crossOwnerEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'inactiveOwnerEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'ownerEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'ownerEventID', :'otherCohostGroupID'),
    (null, 'pending', :'pendingEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'subgroupCohostEventID', :'subgroupID'),
    (current_timestamp, 'approved', :'subgroupOwnedEventID', :'targetGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should include owned, subgroup-owned, approved co-hosted, and cross-community events once
select results_eq(
    format($$
        select event_id
        from list_group_page_events(%L::uuid, 'target-page', array['in-person']::text[])
        order by starts_at, event_id
    $$, :'communityID'),
    format($$
        values
            (%L::uuid),
            (%L::uuid),
            (%L::uuid),
            (%L::uuid)
    $$, :'ownedEventID', :'subgroupOwnedEventID', :'ownerEventID', :'crossOwnerEventID'),
    'Should include owned, subgroup-owned, approved co-hosted, and cross-community events once'
);

-- Should de-duplicate an event that is subgroup-owned and co-hosted by the target group
select is(
    (
        select count(*)::int
        from list_group_page_events(:'communityID'::uuid, 'target-page', array['in-person']::text[])
        where event_id = :'subgroupOwnedEventID'
    ),
    1,
    'Should de-duplicate an event that is subgroup-owned and co-hosted by the target group'
);

-- Should exclude pending co-host rows
select is(
    (
        select count(*)::int
        from list_group_page_events(:'communityID'::uuid, 'target-page', array['in-person']::text[])
        where event_id = :'pendingEventID'
    ),
    0,
    'Should exclude pending co-host rows'
);

-- Should exclude inactive owners
select is(
    (
        select count(*)::int
        from list_group_page_events(:'communityID'::uuid, 'target-page', array['in-person']::text[])
        where event_id = :'inactiveOwnerEventID'
    ),
    0,
    'Should exclude inactive owners'
);

-- Should exclude co-hosting by a subgroup from the parent page
select is(
    (
        select count(*)::int
        from list_group_page_events(:'communityID'::uuid, 'target-page', array['in-person']::text[])
        where event_id = :'subgroupCohostEventID'
    ),
    0,
    'Should exclude co-hosting by a subgroup from the parent page'
);

-- Should return the owner community for cross-community co-hosted events
select is(
    (
        select community_id
        from list_group_page_events(:'communityID'::uuid, 'target-page', array['in-person']::text[])
        where event_id = :'crossOwnerEventID'
    ),
    :'crossCommunityID'::uuid,
    'Should return the owner community for cross-community co-hosted events'
);

-- Should not duplicate events with several co-host rows
select is(
    (
        select count(*)::int
        from list_group_page_events(:'communityID'::uuid, 'target-page', array['in-person']::text[])
        where event_id = :'ownerEventID'
    ),
    1,
    'Should not duplicate events with several co-host rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
