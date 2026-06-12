-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c100000-0000-0000-0000-000000000001'
\set eventCategoryID '0c100000-0000-0000-0000-000000000002'
\set eventID '0c100000-0000-0000-0000-000000000003'
\set eventNoLabelsID '0c100000-0000-0000-0000-000000000004'
\set groupCategoryID '0c100000-0000-0000-0000-000000000005'
\set groupID '0c100000-0000-0000-0000-000000000006'
\set labelAID '0c100000-0000-0000-0000-000000000007'
\set labelZID '0c100000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'cfs-label-community',
    'CFS Label Community',
    'Community for CFS label tests',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name) values
    (:'eventCategoryID', :'communityID', 'Meetup');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'groupID', :'communityID', :'groupCategoryID', 'CFS Label Group', 'cfs-label-group');

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
) values (
    :'eventID',
    :'groupID',
    'Event with labels',
    'event-with-labels',
    'Event with CFS labels',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true
), (
    :'eventNoLabelsID',
    :'groupID',
    'Event no labels',
    'event-no-labels',
    'Event without CFS labels',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true
);

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
