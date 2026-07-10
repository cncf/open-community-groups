-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '0c140000-0000-0000-0000-000000000001'
\set activeEventCategoryID '0c140000-0000-0000-0000-000000000002'
\set activeEventID '0c140000-0000-0000-0000-000000000003'
\set activeEventNullLegacyID '0c140000-0000-0000-0000-000000000004'
\set activeEventSlashID '0c140000-0000-0000-0000-000000000005'
\set activeGroupCategoryID '0c140000-0000-0000-0000-000000000006'
\set activeGroupID '0c140000-0000-0000-0000-000000000007'
\set activeGroupNullLegacyID '0c140000-0000-0000-0000-000000000008'
\set activeGroupSlashID '0c140000-0000-0000-0000-000000000009'
\set deletedEventID '0c140000-0000-0000-0000-00000000000a'
\set deletedGroupID '0c140000-0000-0000-0000-00000000000b'
\set duplicateCommunityID '0c140000-0000-0000-0000-00000000000c'
\set duplicateEventCategoryID '0c140000-0000-0000-0000-00000000000d'
\set duplicateEventID '0c140000-0000-0000-0000-00000000000e'
\set duplicateEventOnlyID '0c140000-0000-0000-0000-00000000000f'
\set duplicateGroupCategoryID '0c140000-0000-0000-0000-000000000010'
\set duplicateGroupID '0c140000-0000-0000-0000-000000000011'
\set duplicateGroupOnlyID '0c140000-0000-0000-0000-000000000012'
\set inactiveCommunityID '0c140000-0000-0000-0000-000000000013'
\set inactiveGroupCategoryID '0c140000-0000-0000-0000-000000000014'
\set inactiveGroupID '0c140000-0000-0000-0000-000000000015'
\set rootGroupID '0c140000-0000-0000-0000-000000000016'
\set scopedDuplicateGroupID '0c140000-0000-0000-0000-000000000017'
\set sharedPathEventID '0c140000-0000-0000-0000-000000000018'
\set sharedPathGroupID '0c140000-0000-0000-0000-000000000019'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    active,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'activeCommunityID',
    true,
    'https://example.com/banner-mobile-active.png',
    'https://example.com/banner-active.png',
    'An active community',
    'Active Community',
    'https://example.com/logo-active.png',
    'active-community'
), (
    :'duplicateCommunityID',
    true,
    'https://example.com/banner-mobile-duplicate.png',
    'https://example.com/banner-duplicate.png',
    'A community for duplicate redirect tests',
    'Duplicate Community',
    'https://example.com/logo-duplicate.png',
    'duplicate-community'
), (
    :'inactiveCommunityID',
    false,
    'https://example.com/banner-mobile-inactive.png',
    'https://example.com/banner-inactive.png',
    'A disabled community',
    'Inactive Community',
    'https://example.com/logo-inactive.png',
    'inactive-community'
);

-- Group categories
insert into group_category (group_category_id, community_id, name) values
    (:'activeGroupCategoryID', :'activeCommunityID', 'Technology'),
    (:'duplicateGroupCategoryID', :'duplicateCommunityID', 'Technology'),
    (:'inactiveGroupCategoryID', :'inactiveCommunityID', 'Technology');

-- Event categories
insert into event_category (event_category_id, community_id, name) values
    (:'activeEventCategoryID', :'activeCommunityID', 'Conference'),
    (:'duplicateEventCategoryID', :'duplicateCommunityID', 'Conference');

-- Groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    slug_pretty,
    description,
    active,
    deleted,
    legacy_url
) values (
    :'activeGroupID',
    :'activeCommunityID',
    :'activeGroupCategoryID',
    'Active Group',
    'active-group',
    'active-pretty',
    'A group with a unique legacy URL',
    true,
    false,
    'https://legacy.example.org/groups/active?source=legacy'
), (
    :'activeGroupSlashID',
    :'activeCommunityID',
    :'activeGroupCategoryID',
    'Active Group Slash',
    'active-group-slash',
    null,
    'A group with a trailing-slash legacy URL',
    true,
    false,
    'https://legacy.example.org/groups/active-slash/'
), (
    :'activeGroupNullLegacyID',
    :'activeCommunityID',
    :'activeGroupCategoryID',
    'Active Group Null Legacy',
    'active-group-null-legacy',
    null,
    'A group without a legacy URL',
    true,
    false,
    null
), (
    :'deletedGroupID',
    :'activeCommunityID',
    :'activeGroupCategoryID',
    'Deleted Group',
    'deleted-group',
    null,
    'A deleted group with a legacy URL',
    false,
    true,
    'https://legacy.example.org/deleted-group'
), (
    :'duplicateGroupID',
    :'duplicateCommunityID',
    :'duplicateGroupCategoryID',
    'Duplicate Group',
    'duplicate-group',
    null,
    'A group sharing a legacy URL',
    true,
    false,
    'https://legacy.example.org/group-duplicate'
), (
    :'duplicateGroupOnlyID',
    :'duplicateCommunityID',
    :'duplicateGroupCategoryID',
    'Duplicate Group Only',
    'duplicate-group-only',
    null,
    'Another group sharing the same legacy URL',
    true,
    false,
    'https://legacy.example.org/group-duplicate'
), (
    :'inactiveGroupID',
    :'inactiveCommunityID',
    :'inactiveGroupCategoryID',
    'Inactive Group',
    'inactive-group',
    null,
    'A group under an inactive community',
    true,
    false,
    'https://legacy.example.org/inactive-group'
), (
    :'rootGroupID',
    :'activeCommunityID',
    :'activeGroupCategoryID',
    'Root Group',
    'root-group',
    null,
    'A group using the site root as legacy URL',
    true,
    false,
    'https://legacy.example.org'
), (
    :'scopedDuplicateGroupID',
    :'duplicateCommunityID',
    :'duplicateGroupCategoryID',
    'Scoped Duplicate Group',
    'scoped-duplicate-group',
    null,
    'A group sharing a legacy URL path across communities',
    true,
    false,
    'https://legacy-duplicate.example.org/groups/active'
), (
    :'sharedPathGroupID',
    :'activeCommunityID',
    :'activeGroupCategoryID',
    'Shared Path Group',
    'shared-path-group',
    null,
    'A group sharing a path with an event',
    true,
    false,
    'https://legacy.example.org/shared-path'
);

-- Events
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    deleted,

    legacy_url,
    published
) values (
    :'activeEventID',
    :'activeEventCategoryID',
    'virtual',
    :'activeGroupID',
    'Active Event',
    'active-event',
    'A published event with a unique legacy URL',
    'UTC',
    false,
    'https://legacy.example.org/events/active?ref=legacy',
    true
), (
    :'activeEventSlashID',
    :'activeEventCategoryID',
    'virtual',
    :'activeGroupID',
    'Active Event Slash',
    'active-event-slash',
    'A published event with a trailing-slash legacy URL',
    'UTC',
    false,
    'https://legacy.example.org/events/active-slash/',
    true
), (
    :'activeEventNullLegacyID',
    :'activeEventCategoryID',
    'virtual',
    :'activeGroupID',
    'Active Event Null Legacy',
    'active-event-null-legacy',
    'A published event without a legacy URL',
    'UTC',
    false,
    null,
    true
), (
    :'deletedEventID',
    :'activeEventCategoryID',
    'virtual',
    :'activeGroupID',
    'Deleted Event',
    'deleted-event',
    'A deleted event with a legacy URL',
    'UTC',
    true,
    'https://legacy.example.org/events/deleted',
    false
), (
    :'duplicateEventID',
    :'duplicateEventCategoryID',
    'virtual',
    :'duplicateGroupID',
    'Duplicate Event',
    'duplicate-event',
    'A published event sharing a legacy URL',
    'UTC',
    false,
    'https://legacy.example.org/events/duplicate',
    true
), (
    :'duplicateEventOnlyID',
    :'duplicateEventCategoryID',
    'virtual',
    :'duplicateGroupID',
    'Duplicate Event Only',
    'duplicate-event-only',
    'Another published event sharing the same legacy URL',
    'UTC',
    false,
    'https://legacy.example.org/events/duplicate',
    true
), (
    :'sharedPathEventID',
    :'activeEventCategoryID',
    'virtual',
    :'activeGroupID',
    'Shared Path Event',
    'shared-path-event',
    'A published event sharing a path with a group',
    'UTC',
    false,
    'https://legacy.example.org/shared-path',
    true
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all unique normalized redirect mappings ordered by legacy path
select is(
    (
        select jsonb_agg(row_to_json(r))
        from list_redirects() r
    ),
    '[
        {"community_name": "active-community", "legacy_path": "/", "new_path": "/active-community/group/root-group"},
        {"community_name": "active-community", "legacy_path": "/events/active", "new_path": "/active-community/group/active-group/event/active-event"},
        {"community_name": "active-community", "legacy_path": "/events/active-slash", "new_path": "/active-community/group/active-group/event/active-event-slash"},
        {"community_name": "active-community", "legacy_path": "/groups/active", "new_path": "/active-community/group/active-group"},
        {"community_name": "active-community", "legacy_path": "/groups/active-slash", "new_path": "/active-community/group/active-group-slash"},
        {"community_name": "duplicate-community", "legacy_path": "/groups/active", "new_path": "/duplicate-community/group/scoped-duplicate-group"}
    ]'::jsonb,
    'Should return all unique normalized redirect mappings ordered by legacy path'
);

-- Should return canonical relative paths without the base URL prefix
select is(
    (
        select new_path
        from list_redirects()
        where community_name = 'active-community'
          and legacy_path = '/groups/active'
    ),
    '/active-community/group/active-group',
    'Should return canonical relative paths without the base URL prefix'
);

-- Should scope duplicate legacy paths by community
select is(
    (
        select jsonb_agg(row_to_json(r))
        from list_redirects() r
        where legacy_path = '/groups/active'
    ),
    '[
        {"community_name": "active-community", "legacy_path": "/groups/active", "new_path": "/active-community/group/active-group"},
        {"community_name": "duplicate-community", "legacy_path": "/groups/active", "new_path": "/duplicate-community/group/scoped-duplicate-group"}
    ]'::jsonb,
    'Should scope duplicate legacy paths by community'
);

-- Should exclude duplicate group legacy paths
select ok(
    not exists(
        select 1
        from list_redirects()
        where legacy_path = '/group-duplicate'
    ),
    'Should exclude duplicate group legacy paths'
);

-- Should exclude duplicate event legacy paths
select ok(
    not exists(
        select 1
        from list_redirects()
        where legacy_path = '/events/duplicate'
    ),
    'Should exclude duplicate event legacy paths'
);

-- Should exclude normalized paths shared by events and groups
select ok(
    not exists(
        select 1
        from list_redirects()
        where legacy_path = '/shared-path'
    ),
    'Should exclude normalized paths shared by events and groups'
);

-- Should exclude inactive, deleted, and null legacy URL records
select ok(
    not exists(
        select 1
        from list_redirects()
        where legacy_path in ('/deleted-group', '/events/deleted', '/inactive-group', '/events/active-event-null-legacy')
    ),
    'Should exclude inactive, deleted, and null legacy URL records'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
