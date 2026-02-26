-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000011'
\set eventID '00000000-0000-0000-0000-000000000021'
\set eventNoLabelsID '00000000-0000-0000-0000-000000000022'
\set groupCategoryID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000041'
\set labelAID '00000000-0000-0000-0000-000000000051'
\set labelZID '00000000-0000-0000-0000-000000000052'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'communityID', 'community', 'Community', 'd', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'groupID', :'communityID', :'groupCategoryID', 'G1', 'g1');

-- Event category
insert into event_category (event_category_id, community_id, name) values
    (:'eventCategoryID', :'communityID', 'Meetup');

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published
) values
    (:'eventID', :'groupID', 'Event with labels', 'event-with-labels', 'd', 'UTC', :'eventCategoryID', 'in-person', true),
    (:'eventNoLabelsID', :'groupID', 'Event no labels', 'event-no-labels', 'd', 'UTC', :'eventCategoryID', 'in-person', true);

-- Event CFS labels
insert into event_cfs_label (event_cfs_label_id, event_id, name, color) values
    (:'labelZID', :'eventID', 'track / z', '#FEE2E2'),
    (:'labelAID', :'eventID', 'track / a', '#DBEAFE');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list labels sorted by name
select is(
    list_event_cfs_labels(:'eventID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'color', '#DBEAFE',
            'event_cfs_label_id', :'labelAID'::uuid,
            'name', 'track / a'
        ),
        jsonb_build_object(
            'color', '#FEE2E2',
            'event_cfs_label_id', :'labelZID'::uuid,
            'name', 'track / z'
        )
    ),
    'Should list labels sorted by name'
);

-- Should return empty list for events without labels
select is(
    list_event_cfs_labels(:'eventNoLabelsID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty list for events without labels'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
