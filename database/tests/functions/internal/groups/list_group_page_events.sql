-- Tests listing public group page events with active subgroup and approved co-hosted events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostedCanceledEventID 'e5050000-0000-0000-0000-000000000001'
\set cohostedEventID 'e5050000-0000-0000-0000-000000000002'
\set cohostedOtherKindEventID 'e5050000-0000-0000-0000-000000000003'
\set cohostedTestEventID 'e5050000-0000-0000-0000-000000000004'
\set cohostedUnpublishedEventID 'e5050000-0000-0000-0000-000000000005'
\set cohostedUnscheduledEventID 'e5050000-0000-0000-0000-000000000006'
\set communityID 'e5050000-0000-0000-0000-000000000007'
\set crossCommunityID 'e5050000-0000-0000-0000-000000000008'
\set crossEventCategoryID 'e5050000-0000-0000-0000-000000000009'
\set crossGroupCategoryID 'e5050000-0000-0000-0000-00000000000a'
\set crossOwnerEventID 'e5050000-0000-0000-0000-00000000000b'
\set crossOwnerGroupID 'e5050000-0000-0000-0000-00000000000c'
\set crossTargetEventID 'e5050000-0000-0000-0000-00000000000d'
\set crossTargetGroupID 'e5050000-0000-0000-0000-00000000000e'
\set eventCategoryID 'e5050000-0000-0000-0000-00000000000f'
\set groupCategoryID 'e5050000-0000-0000-0000-000000000010'
\set inactiveCommunityEventCategoryID 'e5050000-0000-0000-0000-000000000011'
\set inactiveCommunityGroupCategoryID 'e5050000-0000-0000-0000-000000000012'
\set inactiveCommunityID 'e5050000-0000-0000-0000-000000000013'
\set inactiveCommunityOwnerEventID 'e5050000-0000-0000-0000-000000000014'
\set inactiveCommunityOwnerGroupID 'e5050000-0000-0000-0000-000000000015'
\set inactiveOwnerEventID 'e5050000-0000-0000-0000-000000000016'
\set inactiveOwnerGroupID 'e5050000-0000-0000-0000-000000000017'
\set inactiveSubgroupEventID 'e5050000-0000-0000-0000-000000000018'
\set inactiveSubgroupID 'e5050000-0000-0000-0000-000000000019'
\set inactiveTargetEventID 'e5050000-0000-0000-0000-00000000001a'
\set inactiveTargetGroupID 'e5050000-0000-0000-0000-00000000001b'
\set otherCohostGroupID 'e5050000-0000-0000-0000-00000000001c'
\set ownedCanceledEventID 'e5050000-0000-0000-0000-00000000001d'
\set ownedEventID 'e5050000-0000-0000-0000-00000000001e'
\set ownedOtherKindEventID 'e5050000-0000-0000-0000-00000000001f'
\set ownedTestEventID 'e5050000-0000-0000-0000-000000000020'
\set ownedUnpublishedEventID 'e5050000-0000-0000-0000-000000000021'
\set ownedUnscheduledEventID 'e5050000-0000-0000-0000-000000000022'
\set ownerGroupID 'e5050000-0000-0000-0000-000000000023'
\set pendingEventID 'e5050000-0000-0000-0000-000000000024'
\set subgroupCohostEventID 'e5050000-0000-0000-0000-000000000025'
\set subgroupID 'e5050000-0000-0000-0000-000000000026'
\set subgroupOwnedEventID 'e5050000-0000-0000-0000-000000000027'
\set targetGroupID 'e5050000-0000-0000-0000-000000000028'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community of the target group page
select fx_community(:'communityID');

-- Other community owning a co-hosted event
select fx_community(:'crossCommunityID');

-- Inactive community owning a co-hosted event
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

-- Event category for the target community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Event category for the other community
select fx_event_category(:'crossEventCategoryID', :'crossCommunityID');

-- Event category for the inactive community
select fx_event_category(:'inactiveCommunityEventCategoryID', :'inactiveCommunityID');

-- Group category for the target community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category for the other community
select fx_group_category(:'crossGroupCategoryID', :'crossCommunityID');

-- Group category for the inactive community
select fx_group_category(:'inactiveCommunityGroupCategoryID', :'inactiveCommunityID');

-- Group in the other community owning a co-hosted event
select fx_group(:'crossOwnerGroupID', :'crossCommunityID', :'crossGroupCategoryID');

-- Group in the other community sharing the target group slug
select fx_group(:'crossTargetGroupID', :'crossCommunityID', :'crossGroupCategoryID', jsonb_build_object('slug', 'target-page'));

-- Group in the inactive community owning a co-hosted event
select fx_group(:'inactiveCommunityOwnerGroupID', :'inactiveCommunityID', :'inactiveCommunityGroupCategoryID');

-- Inactive group owning a co-hosted event
select fx_group(:'inactiveOwnerGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Inactive target group whose page lists no events
select fx_group(:'inactiveTargetGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'slug', 'inactive-target-page'
));

-- Other group also co-hosting a co-hosted event
select fx_group(:'otherCohostGroupID', :'communityID', :'groupCategoryID');

-- Group owning the co-hosted events
select fx_group(:'ownerGroupID', :'communityID', :'groupCategoryID');

-- Target group resolved by slug or pretty slug
select fx_group(:'targetGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'slug', 'target-page',
    'slug_pretty', 'target-page-pretty'
));

-- Inactive subgroup of the target group
select fx_group(:'inactiveSubgroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'parent_group_id', :'targetGroupID'
));

-- Active subgroup of the target group
select fx_group(:'subgroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'targetGroupID'));

-- Canceled event co-hosted by the target group
select fx_event(:'cohostedCanceledEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', current_timestamp + interval '5 days'
));

-- Public event co-hosted by the target group and another group
select fx_event(:'cohostedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '3 days'
));

-- Event of a kind not requested co-hosted by the target group
select fx_event(:'cohostedOtherKindEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', current_timestamp + interval '6 days'
));

-- Test event co-hosted by the target group
select fx_event(:'cohostedTestEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '7 days',
    'test_event', true
));

-- Unpublished event co-hosted by the target group
select fx_event(:'cohostedUnpublishedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', current_timestamp + interval '8 days'
));

-- Unscheduled event co-hosted by the target group
select fx_event(:'cohostedUnscheduledEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true
));

-- Public event owned by the other community and co-hosted by the target group
select fx_event(:'crossOwnerEventID', :'crossOwnerGroupID', :'crossEventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '4 days'
));

-- Public event owned by the other community group sharing the target group slug
select fx_event(:'crossTargetEventID', :'crossTargetGroupID', :'crossEventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '19 days'
));

-- Public event owned by the inactive community and co-hosted by the target group
select fx_event(:'inactiveCommunityOwnerEventID', :'inactiveCommunityOwnerGroupID', :'inactiveCommunityEventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '9 days'
));

-- Public event owned by the inactive group and co-hosted by the target group
select fx_event(:'inactiveOwnerEventID', :'inactiveOwnerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '10 days'
));

-- Public event owned by the inactive subgroup
select fx_event(:'inactiveSubgroupEventID', :'inactiveSubgroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '11 days'
));

-- Public event owned by the inactive target group
select fx_event(:'inactiveTargetEventID', :'inactiveTargetGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '12 days'
));

-- Canceled event owned by the target group
select fx_event(:'ownedCanceledEventID', :'targetGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', current_timestamp + interval '13 days'
));

-- Public event owned by the target group
select fx_event(:'ownedEventID', :'targetGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Event of a kind not requested owned by the target group
select fx_event(:'ownedOtherKindEventID', :'targetGroupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', current_timestamp + interval '14 days'
));

-- Test event owned by the target group
select fx_event(:'ownedTestEventID', :'targetGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '15 days',
    'test_event', true
));

-- Unpublished event owned by the target group
select fx_event(:'ownedUnpublishedEventID', :'targetGroupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', current_timestamp + interval '16 days'
));

-- Unscheduled event owned by the target group
select fx_event(:'ownedUnscheduledEventID', :'targetGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true
));

-- Public event with a pending co-host invitation for the target group
select fx_event(:'pendingEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '17 days'
));

-- Public event co-hosted by the subgroup only
select fx_event(:'subgroupCohostEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '18 days'
));

-- Public event owned by the subgroup and co-hosted by the target group
select fx_event(:'subgroupOwnedEventID', :'subgroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Co-host rows covering the group page scope
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    (current_timestamp, 'approved', :'cohostedCanceledEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'cohostedEventID', :'otherCohostGroupID'),
    (current_timestamp, 'approved', :'cohostedEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'cohostedOtherKindEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'cohostedTestEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'cohostedUnpublishedEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'cohostedUnscheduledEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'crossOwnerEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'inactiveCommunityOwnerEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'inactiveOwnerEventID', :'targetGroupID'),
    (null, 'pending', :'pendingEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'subgroupCohostEventID', :'subgroupID'),
    (current_timestamp, 'approved', :'subgroupOwnedEventID', :'targetGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list owned, active subgroup, and approved co-hosted public events once with their owner community
select results_eq(
    format(
        $$
        select event_id, community_id, group_id
        from list_group_page_events(%L::uuid, 'target-page', array['in-person']::text[])
        order by starts_at, event_id
        $$,
        :'communityID'
    ),
    format(
        $$
        values
            (%L::uuid, %L::uuid, %L::uuid),
            (%L::uuid, %L::uuid, %L::uuid),
            (%L::uuid, %L::uuid, %L::uuid),
            (%L::uuid, %L::uuid, %L::uuid)
        $$,
        :'ownedEventID', :'communityID', :'targetGroupID',
        :'subgroupOwnedEventID', :'communityID', :'subgroupID',
        :'cohostedEventID', :'communityID', :'ownerGroupID',
        :'crossOwnerEventID', :'crossCommunityID', :'crossOwnerGroupID'
    ),
    'Should list owned, active subgroup, and approved co-hosted public events once with their owner community'
);

-- Should list no events for an inactive target group
select is_empty(
    format(
        $$
        select event_id
        from list_group_page_events(%L::uuid, 'inactive-target-page', array['in-person']::text[])
        $$,
        :'communityID'
    ),
    'Should list no events for an inactive target group'
);

-- Should resolve the target group by pretty slug
select results_eq(
    format(
        $$
        select event_id
        from list_group_page_events(%L::uuid, 'target-page-pretty', array['in-person']::text[])
        order by starts_at, event_id
        $$,
        :'communityID'
    ),
    format(
        $$
        values
            (%L::uuid),
            (%L::uuid),
            (%L::uuid),
            (%L::uuid)
        $$,
        :'ownedEventID',
        :'subgroupOwnedEventID',
        :'cohostedEventID',
        :'crossOwnerEventID'
    ),
    'Should resolve the target group by pretty slug'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
