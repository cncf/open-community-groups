-- Tests locking active event cancellation targets.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeEventID 'd4060000-0000-0000-0000-000000000001'
\set canceledEventID 'd4060000-0000-0000-0000-000000000002'
\set communityID 'd4060000-0000-0000-0000-000000000003'
\set deletedEventID 'd4060000-0000-0000-0000-000000000004'
\set eventCategoryID 'd4060000-0000-0000-0000-000000000005'
\set groupCategoryID 'd4060000-0000-0000-0000-000000000006'
\set groupID 'd4060000-0000-0000-0000-000000000007'
\set missingEventID 'd4060000-0000-0000-0000-000000000008'
\set otherEventID 'd4060000-0000-0000-0000-000000000009'
\set otherGroupID 'd4060000-0000-0000-0000-000000000010'
\set pastEventID 'd4060000-0000-0000-0000-000000000011'
\set secondActiveEventID 'd4060000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the cancellation lock fixtures
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.test/mobile.png',
    'https://example.test/banner.png',
    :'communityID',
    'Community',
    'Community',
    'https://example.test/logo.png',
    'cancellation-lock-community'
);

-- Event category shared by the cancellation lock events
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category shared by the cancellation lock groups
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Groups used to verify cancellation lock ownership
insert into "group" (community_id, group_category_id, group_id, name, slug) values
    (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group'),
    (:'communityID', :'groupCategoryID', :'otherGroupID', 'Other Group', 'other-group');

-- Events covering active, canceled, deleted, past, and cross-group targets
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone,

    canceled,
    deleted,
    deleted_at,
    ends_at
) values
    ('Active', :'eventCategoryID', :'activeEventID', 'virtual', :'groupID', 'Active', 'active', now() + interval '1 day', 'UTC', false, false, null, now() + interval '1 day 1 hour'),
    ('Canceled', :'eventCategoryID', :'canceledEventID', 'virtual', :'groupID', 'Canceled', 'canceled', now() + interval '2 days', 'UTC', true, false, null, now() + interval '2 days 1 hour'),
    ('Deleted', :'eventCategoryID', :'deletedEventID', 'virtual', :'groupID', 'Deleted', 'deleted', now() + interval '3 days', 'UTC', false, true, current_timestamp, now() + interval '3 days 1 hour'),
    ('Other', :'eventCategoryID', :'otherEventID', 'virtual', :'otherGroupID', 'Other', 'other', now() + interval '4 days', 'UTC', false, false, null, now() + interval '4 days 1 hour'),
    ('Past', :'eventCategoryID', :'pastEventID', 'virtual', :'groupID', 'Past', 'past', now() - interval '2 hours', 'UTC', false, false, null, now() - interval '1 hour'),
    ('Second active', :'eventCategoryID', :'secondActiveEventID', 'virtual', :'groupID', 'Second active', 'second-active', now() + interval '5 days', 'UTC', false, false, null, now() + interval '5 days 1 hour');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should lock unique active targets regardless of input order
select lives_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, array[%L::uuid, %L::uuid, %L::uuid])$$,
        :'groupID',
        :'secondActiveEventID',
        :'activeEventID',
        :'secondActiveEventID'
    ),
    'Should lock unique active targets regardless of input order'
);

-- Should reject a canceled target
select throws_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'canceledEventID'
    ),
    'one or more events were not found or inactive',
    'Should reject a canceled target'
);

-- Should reject a cross-group target
select throws_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'otherEventID'
    ),
    'one or more events were not found or inactive',
    'Should reject a cross-group target'
);

-- Should reject a deleted target
select throws_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'deletedEventID'
    ),
    'one or more events were not found or inactive',
    'Should reject a deleted target'
);

-- Should reject an empty target list
select throws_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, '{}'::uuid[])$$,
        :'groupID'
    ),
    'event_ids cannot be empty',
    'Should reject an empty target list'
);

-- Should reject a missing target
select throws_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'missingEventID'
    ),
    'one or more events were not found or inactive',
    'Should reject a missing target'
);

-- Should reject a past target
select throws_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'pastEventID'
    ),
    'one or more events were not found or inactive',
    'Should reject a past target'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
