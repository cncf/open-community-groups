-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a310000-0000-0000-0000-000000000001'
\set event2ID '3a310000-0000-0000-0000-000000000002'
\set eventCategoryID '3a310000-0000-0000-0000-000000000003'
\set eventID '3a310000-0000-0000-0000-000000000004'
\set groupCategoryID '3a310000-0000-0000-0000-000000000005'
\set groupID '3a310000-0000-0000-0000-000000000006'
\set label1ID '3a310000-0000-0000-0000-000000000007'
\set label2ID '3a310000-0000-0000-0000-000000000008'
\set labelOtherID '3a310000-0000-0000-0000-000000000009'

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
    'A test community for CFS labels',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'CFS Label Group', 'cfs-label-group');

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values
    (
        :'eventID',
        :'groupID',
        'Labels Event',
        'labels-event',
        'Event used for CFS label sync tests',
        'UTC',
        :'eventCategoryID',
        'in-person'
    ),
    (
        :'event2ID',
        :'groupID',
        'Other Labels Event',
        'other-labels-event',
        'Other event used for invalid label lookups',
        'UTC',
        :'eventCategoryID',
        'in-person'
    );

-- Event CFS labels
insert into event_cfs_label (event_cfs_label_id, event_id, name, color) values
    (:'label1ID', :'eventID', 'Track / Backend', '#DBEAFE'),
    (:'label2ID', :'eventID', 'Track / Frontend', '#FEE2E2'),
    (:'labelOtherID', :'event2ID', 'Track / Other', '#CCFBF1');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should upsert payload labels and remove omitted labels
select lives_ok(
    format(
        $$select sync_event_cfs_labels(
            '%s'::uuid,
            '[
                {"event_cfs_label_id": "%s", "name": "Track / Platform", "color": "#C7D2FE"},
                {"name": "Track / Data", "color": "#DCFCE7"}
            ]'::jsonb
        )$$,
        :'eventID',
        :'label1ID'
    ),
    'Should upsert payload labels and remove omitted labels'
);

-- Should update existing labels
select is(
    (
        select jsonb_build_object(
            'color', color,
            'name', name
        )
        from event_cfs_label
        where event_cfs_label_id = :'label1ID'::uuid
    ),
    jsonb_build_object(
        'color', '#C7D2FE',
        'name', 'Track / Platform'
    ),
    'Should update existing labels'
);

-- Should insert new labels from the payload
select is(
    (select count(*) from event_cfs_label where event_id = :'eventID'::uuid and name = 'Track / Data'),
    1::bigint,
    'Should insert new labels from the payload'
);

-- Should remove labels omitted from the payload
select is(
    (select count(*) from event_cfs_label where event_cfs_label_id = :'label2ID'::uuid),
    0::bigint,
    'Should remove labels omitted from the payload'
);

-- Should delete all labels when payload is omitted
select lives_ok(
    format(
        $$select sync_event_cfs_labels('%s'::uuid, null)$$,
        :'eventID'
    ),
    'Should delete all labels when payload is omitted'
);

-- Should leave no labels after deleting with a null payload
select is(
    (select count(*) from event_cfs_label where event_id = :'eventID'::uuid),
    0::bigint,
    'Should leave no labels after deleting with a null payload'
);

-- Should reject updating a label that belongs to another event
select throws_ok(
    format(
        $$select sync_event_cfs_labels(
            '%s'::uuid,
            '[{"event_cfs_label_id": "%s", "name": "Track / Invalid", "color": "#FDE68A"}]'::jsonb
        )$$,
        :'eventID',
        :'labelOtherID'
    ),
    format('event CFS label %s not found for event %s', :'labelOtherID', :'eventID'),
    'Should reject updating a label that belongs to another event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
