-- Tests get_group_past_events returns the latest de-duplicated past group page events up to the limit.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set childEventID '6a020000-0000-0000-0000-000000000001'
\set childGroupID '6a020000-0000-0000-0000-000000000002'
\set cohostedEventID '6a020000-0000-0000-0000-000000000003'
\set communityID '6a020000-0000-0000-0000-000000000004'
\set eventCategoryID '6a020000-0000-0000-0000-000000000005'
\set futureEventID '6a020000-0000-0000-0000-000000000006'
\set groupCategoryID '6a020000-0000-0000-0000-000000000007'
\set groupID '6a020000-0000-0000-0000-000000000008'
\set oldestEventID '6a020000-0000-0000-0000-000000000009'
\set ownedEventID '6a020000-0000-0000-0000-00000000000a'
\set ownerGroupID '6a020000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for group event lookup
select fx_community(:'communityID');

-- Event category for the seeded events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category for the seeded groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Parent group resolved by slug
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'city', 'San Francisco',
    'country_code', 'US',
    'country_name', 'United States',
    'slug', 'test-group',
    'state', 'CA'
));

-- Group owning the co-hosted event
select fx_group(:'ownerGroupID', :'communityID', :'groupCategoryID');

-- Child group owning an event also co-hosted by the parent group
select fx_group(:'childGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'groupID'));

-- Past child group event listed once although it is also co-hosted
select fx_event(:'childEventID', :'childGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '3 months' + interval '2 hours',
    'event_kind_id', 'hybrid',
    'published', true,
    'starts_at', now() - interval '3 months'
));

-- Most recent past event co-hosted by the parent group
select fx_event(:'cohostedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 month' + interval '2 hours',
    'published', true,
    'starts_at', now() - interval '1 month'
));

-- Future event excluded from past events
select fx_event(:'futureEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 year' + interval '2 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 year'
));

-- Oldest past event left out by the limit
select fx_event(:'oldestEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 year' + interval '2 hours',
    'published', true,
    'starts_at', now() - interval '1 year'
));

-- Past event owned by the parent group
select fx_event(:'ownedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '6 months' + interval '2 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() - interval '6 months'
));

-- Approved co-host rows crediting the parent group
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    (current_timestamp, 'approved', :'childEventID', :'groupID'),
    (current_timestamp, 'approved', :'cohostedEventID', :'groupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the latest past events de-duplicated and limited as JSON
select is(
    get_group_past_events(:'communityID'::uuid, 'test-group', array['in-person', 'virtual', 'hybrid'], 3)::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'ownerGroupID'::uuid, :'cohostedEventID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'childGroupID'::uuid, :'childEventID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'ownedEventID'::uuid)::jsonb
    ),
    'Should return the latest past events de-duplicated and limited as JSON'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
