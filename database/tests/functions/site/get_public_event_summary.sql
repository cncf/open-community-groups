-- Tests returning the summary of publicly visible events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5ea50000-0000-0000-0000-000000000001'
\set deletedEventID '5ea50000-0000-0000-0000-000000000002'
\set deletedGroupEventID '5ea50000-0000-0000-0000-000000000003'
\set deletedGroupID '5ea50000-0000-0000-0000-000000000004'
\set eventCategoryID '5ea50000-0000-0000-0000-000000000005'
\set eventID '5ea50000-0000-0000-0000-000000000006'
\set groupCategoryID '5ea50000-0000-0000-0000-000000000007'
\set groupID '5ea50000-0000-0000-0000-000000000008'
\set inactiveCommunityEventCategoryID '5ea50000-0000-0000-0000-000000000009'
\set inactiveCommunityEventID '5ea50000-0000-0000-0000-000000000010'
\set inactiveCommunityGroupCategoryID '5ea50000-0000-0000-0000-000000000011'
\set inactiveCommunityGroupID '5ea50000-0000-0000-0000-000000000012'
\set inactiveCommunityID '5ea50000-0000-0000-0000-000000000013'
\set inactiveGroupEventID '5ea50000-0000-0000-0000-000000000014'
\set inactiveGroupID '5ea50000-0000-0000-0000-000000000015'
\set unknownEventID '5ea50000-0000-0000-0000-000000000016'
\set unpublishedEventID '5ea50000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community owning the events
select fx_community(:'communityID', jsonb_build_object('active', true));

-- Inactive community
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

-- Event category of the active community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Event category of the inactive community
select fx_event_category(:'inactiveCommunityEventCategoryID', :'inactiveCommunityID');

-- Group category of the active community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category of the inactive community
select fx_group_category(:'inactiveCommunityGroupCategoryID', :'inactiveCommunityID');

-- Active group owning the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Deleted group
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Active group of the inactive community
select fx_group(:'inactiveCommunityGroupID', :'inactiveCommunityID', :'inactiveCommunityGroupCategoryID', jsonb_build_object(
    'active', true
));

-- Inactive group
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Published event of an active group
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Deleted event
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('deleted', true));

-- Published event of a deleted group
select fx_event(:'deletedGroupEventID', :'deletedGroupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Published event of an active group in the inactive community
select fx_event(
    :'inactiveCommunityEventID',
    :'inactiveCommunityGroupID',
    :'inactiveCommunityEventCategoryID',
    jsonb_build_object('published', true)
);

-- Published event of an inactive group
select fx_event(:'inactiveGroupEventID', :'inactiveGroupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Unpublished event of an active group
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', false));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return null for a deleted event
select is(
    get_public_event_summary(:'deletedEventID'::uuid)::jsonb,
    null,
    'Should return null for a deleted event'
);

-- Should return null for an event of a deleted group
select is(
    get_public_event_summary(:'deletedGroupEventID'::uuid)::jsonb,
    null,
    'Should return null for an event of a deleted group'
);

-- Should return null for an event of an inactive community
select is(
    get_public_event_summary(:'inactiveCommunityEventID'::uuid)::jsonb,
    null,
    'Should return null for an event of an inactive community'
);

-- Should return null for an event of an inactive group
select is(
    get_public_event_summary(:'inactiveGroupEventID'::uuid)::jsonb,
    null,
    'Should return null for an event of an inactive group'
);

-- Should return null for an unknown event
select is(
    get_public_event_summary(:'unknownEventID'::uuid)::jsonb,
    null,
    'Should return null for an unknown event'
);

-- Should return null for an unpublished event
select is(
    get_public_event_summary(:'unpublishedEventID'::uuid)::jsonb,
    null,
    'Should return null for an unpublished event'
);

-- Should return the summary of a public event
select is(
    get_public_event_summary(:'eventID'::uuid)::jsonb,
    get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
    'Should return the summary of a public event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
