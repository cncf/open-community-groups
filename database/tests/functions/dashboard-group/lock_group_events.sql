-- Tests locking a group and its event mutation targets.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeEventID 'd4070000-0000-0000-0000-000000000001'
\set communityID 'd4070000-0000-0000-0000-000000000002'
\set deletedEventID 'd4070000-0000-0000-0000-000000000003'
\set deletedGroupID 'd4070000-0000-0000-0000-000000000012'
\set eventCategoryID 'd4070000-0000-0000-0000-000000000004'
\set groupCategoryID 'd4070000-0000-0000-0000-000000000005'
\set groupID 'd4070000-0000-0000-0000-000000000006'
\set missingEventID 'd4070000-0000-0000-0000-000000000007'
\set missingGroupID 'd4070000-0000-0000-0000-000000000008'
\set otherEventID 'd4070000-0000-0000-0000-000000000009'
\set otherGroupID 'd4070000-0000-0000-0000-000000000010'
\set secondActiveEventID 'd4070000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the group event lock fixtures
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
    'group-event-lock-community'
);

-- Event category shared by the group event lock targets
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category shared by the group event lock owners
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Groups used to verify event ownership
insert into "group" (community_id, group_category_id, group_id, name, slug) values
    (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group'),
    (:'communityID', :'groupCategoryID', :'otherGroupID', 'Other Group', 'other-group');

-- Deleted group rejected as an inactive event owner
insert into "group" (
    group_id,
    active,
    community_id,
    deleted,
    group_category_id,
    name,
    slug
) values (
    :'deletedGroupID',
    false,
    :'communityID',
    true,
    :'groupCategoryID',
    'Deleted Group',
    'deleted-group'
);

-- Events covering active, deleted, and cross-group targets
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone,

    deleted,
    deleted_at
) values
    ('Active', :'eventCategoryID', :'activeEventID', 'virtual', :'groupID', 'Active', 'active', 'UTC', false, null),
    ('Deleted', :'eventCategoryID', :'deletedEventID', 'virtual', :'groupID', 'Deleted', 'deleted', 'UTC', true, current_timestamp),
    ('Other', :'eventCategoryID', :'otherEventID', 'virtual', :'otherGroupID', 'Other', 'other', 'UTC', false, null),
    ('Second active', :'eventCategoryID', :'secondActiveEventID', 'virtual', :'groupID', 'Second active', 'second-active', 'UTC', false, null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should lock unique active targets regardless of input order
select lives_ok(
    format(
        $$select lock_group_events(%L::uuid, array[%L::uuid, %L::uuid, %L::uuid])$$,
        :'groupID',
        :'secondActiveEventID',
        :'activeEventID',
        :'secondActiveEventID'
    ),
    'Should lock unique active targets regardless of input order'
);

-- Should reject a cross-group target
select throws_ok(
    format(
        $$select lock_group_events(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'otherEventID'
    ),
    'one or more events were not found or inactive',
    'Should reject a cross-group target'
);

-- Should reject a deleted group
select throws_ok(
    format(
        $$select lock_group_events(%L::uuid, array[%L::uuid])$$,
        :'deletedGroupID',
        :'activeEventID'
    ),
    'group not found or inactive',
    'Should reject a deleted group'
);

-- Should reject a deleted target
select throws_ok(
    format(
        $$select lock_group_events(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'deletedEventID'
    ),
    'one or more events were not found or inactive',
    'Should reject a deleted target'
);

-- Should reject an empty target list
select throws_ok(
    format(
        $$select lock_group_events(%L::uuid, '{}'::uuid[])$$,
        :'groupID'
    ),
    'event_ids cannot be empty',
    'Should reject an empty target list'
);

-- Should reject a missing group
select throws_ok(
    format(
        $$select lock_group_events(%L::uuid, array[%L::uuid])$$,
        :'missingGroupID',
        :'activeEventID'
    ),
    'group not found or inactive',
    'Should reject a missing group'
);

-- Should reject a missing target
select throws_ok(
    format(
        $$select lock_group_events(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'missingEventID'
    ),
    'one or more events were not found or inactive',
    'Should reject a missing target'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
