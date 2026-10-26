-- Tests get_group_upcoming_events returns the earliest de-duplicated upcoming group page events up to the limit.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set altCommunityID '6a030000-0000-0000-0000-000000000001'
\set altEventCategoryID '6a030000-0000-0000-0000-000000000002'
\set altGroupCategoryID '6a030000-0000-0000-0000-000000000003'
\set altGroupID '6a030000-0000-0000-0000-000000000004'
\set childEventID '6a030000-0000-0000-0000-000000000005'
\set childGroupID '6a030000-0000-0000-0000-000000000006'
\set cohostedEventID '6a030000-0000-0000-0000-000000000007'
\set communityID '6a030000-0000-0000-0000-000000000008'
\set eventCategoryID '6a030000-0000-0000-0000-000000000009'
\set groupCategoryID '6a030000-0000-0000-0000-00000000000a'
\set groupID '6a030000-0000-0000-0000-00000000000b'
\set ownedEventID '6a030000-0000-0000-0000-00000000000c'
\set ownerGroupID '6a030000-0000-0000-0000-00000000000d'
\set pastEventID '6a030000-0000-0000-0000-00000000000e'
\set tiedEventID '6a030000-0000-0000-0000-00000000000f'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for group event lookup
select fx_community(:'communityID');

-- Community whose ID sorts first, so its tied event reaches the caller first
select fx_community(:'altCommunityID');

-- Event category for the event in the other community
select fx_event_category(:'altEventCategoryID', :'altCommunityID');

-- Group category for the group in the other community
select fx_group_category(:'altGroupCategoryID', :'altCommunityID');

-- Group in the other community owning the tied co-hosted event
select fx_group(:'altGroupID', :'altCommunityID', :'altGroupCategoryID');

-- Event category for the seeded events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category for the seeded groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Parent group resolved by slug
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'city', 'Los Angeles',
    'country_code', 'US',
    'country_name', 'United States',
    'slug', 'test-group',
    'state', 'CA'
));

-- Group owning the co-hosted event
select fx_group(:'ownerGroupID', :'communityID', :'groupCategoryID');

-- Child group owning an event also co-hosted by the parent group
select fx_group(:'childGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'groupID'));

-- Upcoming child group event listed once although it is also co-hosted
select fx_event(:'childEventID', :'childGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '15 days' + interval '2 hours',
    'event_kind_id', 'hybrid',
    'published', true,
    'starts_at', now() + interval '15 days'
));

-- Earliest upcoming event co-hosted by the parent group
select fx_event(:'cohostedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '5 days' + interval '2 hours',
    'published', true,
    'starts_at', now() + interval '5 days'
));

-- Upcoming co-hosted event tied with the owned event; its community sorts first,
-- so only the event ID tiebreak orders it after the owned event
select fx_event(:'tiedEventID', :'altGroupID', :'altEventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 month' + interval '4 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 month'
));

-- Upcoming event owned by the parent group
select fx_event(:'ownedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 month' + interval '2 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 month'
));

-- Past event excluded from upcoming events
select fx_event(:'pastEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 year' + interval '2 hours',
    'published', true,
    'starts_at', now() - interval '1 year'
));

-- Approved co-host rows crediting the parent group
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    (current_timestamp, 'approved', :'childEventID', :'groupID'),
    (current_timestamp, 'approved', :'cohostedEventID', :'groupID'),
    (current_timestamp, 'approved', :'tiedEventID', :'groupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should order tied future events by event ID
select is(
    (
        select jsonb_agg(event_item->>'event_id')
        from jsonb_array_elements(
            get_group_upcoming_events(:'communityID'::uuid, 'test-group', array['virtual'], 10)::jsonb
        ) event_item
    ),
    jsonb_build_array(:'ownedEventID', :'tiedEventID'),
    'Should order tied future events by event ID'
);

-- Should return empty array with non-existing group slug
select is(
    get_group_upcoming_events(:'communityID'::uuid, 'non-existing-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    '[]'::jsonb,
    'Should return empty array with non-existing group slug'
);

-- Should return the earliest upcoming events de-duplicated and limited as JSON
select is(
    get_group_upcoming_events(:'communityID'::uuid, 'test-group', array['in-person', 'virtual', 'hybrid'], 3)::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'ownerGroupID'::uuid, :'cohostedEventID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'childGroupID'::uuid, :'childEventID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'ownedEventID'::uuid)::jsonb
    ),
    'Should return the earliest upcoming events de-duplicated and limited as JSON'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
