-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '6a030000-0000-0000-0000-000000000001'
\set deletedChildEventID '6a030000-0000-0000-0000-00000000000f'
\set deletedChildGroupID '6a030000-0000-0000-0000-00000000000c'
\set event1ID '6a030000-0000-0000-0000-000000000002'
\set event2ID '6a030000-0000-0000-0000-000000000003'
\set event3ID '6a030000-0000-0000-0000-000000000004'
\set event4ID '6a030000-0000-0000-0000-000000000005'
\set event5ID '6a030000-0000-0000-0000-000000000006'
\set childEventID '6a030000-0000-0000-0000-00000000000d'
\set childGroupID '6a030000-0000-0000-0000-00000000000a'
\set eventCategoryID '6a030000-0000-0000-0000-000000000007'
\set groupCategoryID '6a030000-0000-0000-0000-000000000008'
\set groupID '6a030000-0000-0000-0000-000000000009'
\set inactiveChildEventID '6a030000-0000-0000-0000-00000000000e'
\set inactiveChildGroupID '6a030000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and categories for group event lookup
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

-- Parent group resolved by slug
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'city', 'Los Angeles',
    'country_code', 'US',
    'country_name', 'United States',
    'slug', 'test-group',
    'state', 'CA'
));

-- Child groups used by inherited event lookup
select fx_group(:'childGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'groupID'));
select fx_group(:'inactiveChildGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'parent_group_id', :'groupID'
));
select fx_group(:'deletedChildGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true,
    'parent_group_id', :'groupID'
));

-- Events covering upcoming filters and ordering
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 year' + interval '2 hours',
    'published', true,
    'starts_at', now() - interval '1 year'
));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 month' + interval '2 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 month'
));
select fx_event(:'event3ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '2 months' + interval '2 hours',
    'event_kind_id', 'hybrid',
    'published', true,
    'starts_at', now() + interval '2 months',
    'test_event', true
));
select fx_event(:'event4ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '3 months' + interval '2 hours',
    'starts_at', now() + interval '3 months'
));

-- Child group events covering active and inactive children
select fx_event(:'childEventID', :'childGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '15 days' + interval '2 hours',
    'published', true,
    'starts_at', now() + interval '15 days'
));
select fx_event(:'inactiveChildEventID', :'inactiveChildGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '10 days' + interval '2 hours',
    'published', true,
    'starts_at', now() + interval '10 days'
));
select fx_event(:'deletedChildEventID', :'deletedChildGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '12 days' + interval '2 hours',
    'published', true,
    'starts_at', now() + interval '12 days'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return published non-test future events ordered by date ASC as JSON
select is(
    get_group_upcoming_events(:'communityID'::uuid, 'test-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'childGroupID'::uuid, :'childEventID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should return published non-test future events from the group and active children ordered by date ASC as JSON'
);

-- Should return empty array with non-existing group slug
select is(
    get_group_upcoming_events(:'communityID'::uuid, 'non-existing-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    '[]'::jsonb,
    'Should return empty array with non-existing group slug'
);

-- Intentional mid-test seed: verifies deterministic ordering for tied future events
insert into event (
    event_id,
    name,
    slug,
    description,
    description_short,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    starts_at,
    ends_at,
    logo_url,
    venue_city
) values (
    :'event5ID',
    'Future Event 4',
    'future-event-4',
    'A future event with a tied start time',
    'A future event with a tied start time',
    'UTC',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    true,
    now() + interval '1 month',
    now() + interval '1 month' + interval '4 hours',
    'https://example.com/future-event-4.png',
    'Online'
);

-- Should order tied future events by event ID
select is(
    (
        select jsonb_agg(event_item->>'event_id')
        from jsonb_array_elements(
            get_group_upcoming_events(:'communityID'::uuid, 'test-group', array['virtual'], 10)::jsonb
        ) event_item
    ),
    jsonb_build_array(:'event2ID', :'event5ID'),
    'Should order tied future events by event ID'
);

-- Should resolve upcoming events by pretty slug
update "group" set slug_pretty = 'test-group-pretty' where group_id = :'groupID';
select is(
    get_group_upcoming_events(:'communityID'::uuid, 'test-group-pretty', array['virtual'], 10)::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should resolve upcoming events by pretty slug'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
