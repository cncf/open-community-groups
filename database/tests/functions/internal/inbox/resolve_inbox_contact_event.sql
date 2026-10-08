-- Tests resolving events that accept inbox contact.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '1b020000-0000-0000-0000-000000000001'
\set cohostGroupID '1b020000-0000-0000-0000-000000000002'
\set communityID '1b020000-0000-0000-0000-000000000003'
\set eventCategoryID '1b020000-0000-0000-0000-000000000007'
\set eventID '1b020000-0000-0000-0000-000000000008'
\set groupCategoryID '1b020000-0000-0000-0000-000000000009'
\set groupID '1b020000-0000-0000-0000-000000000010'
\set otherCommunityID '1b020000-0000-0000-0000-000000000013'
\set pastEventID '1b020000-0000-0000-0000-000000000014'
\set unpublishedEventID '1b020000-0000-0000-0000-000000000015'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the events
select fx_community(:'communityID');

-- Community used by the cross-community scenario
select fx_community(:'otherCommunityID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group owning the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Active group co-hosting the published event
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');

-- Published event co-hosted by another group
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Published canceled event
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true
));

-- Published past event
select fx_event(:'pastEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2020-01-01 12:00:00+00',
    'published', true,
    'starts_at', '2020-01-01 10:00:00+00'
));

-- Unpublished event
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID');

-- Approved co-host of the published event
insert into event_cohost (event_id, group_id, event_cohost_status_id, approved_at)
values (:'eventID', :'cohostGroupID', 'approved', current_timestamp);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should resolve a canceled event
select results_eq(
    format($$select * from resolve_inbox_contact_event(%L::uuid, %L::uuid)$$, :'communityID', :'canceledEventID'),
    format($$values (%L::uuid, %L::uuid)$$, :'canceledEventID', :'groupID'),
    'Should resolve a canceled event'
);

-- Should resolve a co-hosted event to its owning group
select results_eq(
    format($$select * from resolve_inbox_contact_event(%L::uuid, %L::uuid)$$, :'communityID', :'eventID'),
    format($$values (%L::uuid, %L::uuid)$$, :'eventID', :'groupID'),
    'Should resolve a co-hosted event to its owning group'
);

-- Should resolve a past event
select results_eq(
    format($$select * from resolve_inbox_contact_event(%L::uuid, %L::uuid)$$, :'communityID', :'pastEventID'),
    format($$values (%L::uuid, %L::uuid)$$, :'pastEventID', :'groupID'),
    'Should resolve a past event'
);

-- Should skip an event of another community
select is_empty(
    format($$select * from resolve_inbox_contact_event(%L::uuid, %L::uuid)$$, :'otherCommunityID', :'eventID'),
    'Should skip an event of another community'
);

-- Should skip an unknown event
select is_empty(
    format($$select * from resolve_inbox_contact_event(%L::uuid, %L::uuid)$$, :'communityID', :'groupID'),
    'Should skip an unknown event'
);

-- Should skip an unpublished event
select is_empty(
    format($$select * from resolve_inbox_contact_event(%L::uuid, %L::uuid)$$, :'communityID', :'unpublishedEventID'),
    'Should skip an unpublished event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
