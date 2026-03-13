-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '00000000-0000-0000-0000-000000000001'
\set duplicateCommunityID '00000000-0000-0000-0000-000000000002'
\set inactiveCommunityID '00000000-0000-0000-0000-000000000003'
\set activeEventCategoryID '00000000-0000-0000-0000-000000000011'
\set activeGroupCategoryID '00000000-0000-0000-0000-000000000021'
\set duplicateEventCategoryID '00000000-0000-0000-0000-000000000012'
\set duplicateGroupCategoryID '00000000-0000-0000-0000-000000000022'
\set inactiveGroupCategoryID '00000000-0000-0000-0000-000000000023'
\set activeEventID '00000000-0000-0000-0000-000000000101'
\set activeEventSlashID '00000000-0000-0000-0000-000000000105'
\set activeEventNullLegacyID '00000000-0000-0000-0000-000000000106'
\set activeGroupID '00000000-0000-0000-0000-000000000201'
\set activeGroupSlashID '00000000-0000-0000-0000-000000000207'
\set activeGroupNullLegacyID '00000000-0000-0000-0000-000000000208'
\set duplicateEventID '00000000-0000-0000-0000-000000000102'
\set duplicateEventOnlyID '00000000-0000-0000-0000-000000000103'
\set duplicateGroupID '00000000-0000-0000-0000-000000000202'
\set duplicateGroupOnlyID '00000000-0000-0000-0000-000000000203'
\set inactiveGroupID '00000000-0000-0000-0000-000000000204'
\set rootGroupID '00000000-0000-0000-0000-000000000206'
\set sharedPathGroupID '00000000-0000-0000-0000-000000000209'
\set sharedPathEventID '00000000-0000-0000-0000-000000000107'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (:'activeCommunityID', 'active-community', 'Active Community', 'An active community', 'https://example.com/logo-active.png', 'https://example.com/banner-mobile-active.png', 'https://example.com/banner-active.png'),
    (:'duplicateCommunityID', 'duplicate-community', 'Duplicate Community', 'A community for duplicate redirect tests', 'https://example.com/logo-duplicate.png', 'https://example.com/banner-mobile-duplicate.png', 'https://example.com/banner-duplicate.png'),
    (:'inactiveCommunityID', 'inactive-community', 'Inactive Community', 'A disabled community', 'https://example.com/logo-inactive.png', 'https://example.com/banner-mobile-inactive.png', 'https://example.com/banner-inactive.png');

update community
set active = false
where community_id = :'inactiveCommunityID'::uuid;

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
    description,
    legacy_url
) values
    (:'activeGroupID', :'activeCommunityID', :'activeGroupCategoryID', 'Active Group', 'active-group', 'A group with a unique legacy URL', 'https://legacy.example.org/groups/active?source=legacy'),
    (:'activeGroupSlashID', :'activeCommunityID', :'activeGroupCategoryID', 'Active Group Slash', 'active-group-slash', 'A group with a trailing-slash legacy URL', 'https://legacy.example.org/groups/active-slash/'),
    (:'activeGroupNullLegacyID', :'activeCommunityID', :'activeGroupCategoryID', 'Active Group Null Legacy', 'active-group-null-legacy', 'A group without a legacy URL', null),
    (:'duplicateGroupID', :'duplicateCommunityID', :'duplicateGroupCategoryID', 'Duplicate Group', 'duplicate-group', 'A group sharing a legacy URL', 'https://legacy.example.org/group-duplicate'),
    (:'duplicateGroupOnlyID', :'duplicateCommunityID', :'duplicateGroupCategoryID', 'Duplicate Group Only', 'duplicate-group-only', 'Another group sharing the same legacy URL', 'https://legacy.example.org/group-duplicate'),
    (:'inactiveGroupID', :'inactiveCommunityID', :'inactiveGroupCategoryID', 'Inactive Group', 'inactive-group', 'A group under an inactive community', 'https://legacy.example.org/inactive-group'),
    (:'rootGroupID', :'activeCommunityID', :'activeGroupCategoryID', 'Root Group', 'root-group', 'A group using the site root as legacy URL', 'https://legacy.example.org'),
    (:'sharedPathGroupID', :'activeCommunityID', :'activeGroupCategoryID', 'Shared Path Group', 'shared-path-group', 'A group sharing a path with an event', 'https://legacy.example.org/shared-path');

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

    legacy_url,
    published
) values
    (:'activeEventID', :'activeEventCategoryID', 'virtual', :'activeGroupID', 'Active Event', 'active-event', 'A published event with a unique legacy URL', 'UTC', 'https://legacy.example.org/events/active?ref=legacy', true),
    (:'activeEventSlashID', :'activeEventCategoryID', 'virtual', :'activeGroupID', 'Active Event Slash', 'active-event-slash', 'A published event with a trailing-slash legacy URL', 'UTC', 'https://legacy.example.org/events/active-slash/', true),
    (:'activeEventNullLegacyID', :'activeEventCategoryID', 'virtual', :'activeGroupID', 'Active Event Null Legacy', 'active-event-null-legacy', 'A published event without a legacy URL', 'UTC', null, true),
    (:'duplicateEventID', :'duplicateEventCategoryID', 'virtual', :'duplicateGroupID', 'Duplicate Event', 'duplicate-event', 'A published event sharing a legacy URL', 'UTC', 'https://legacy.example.org/events/duplicate', true),
    (:'duplicateEventOnlyID', :'duplicateEventCategoryID', 'virtual', :'duplicateGroupID', 'Duplicate Event Only', 'duplicate-event-only', 'Another published event sharing the same legacy URL', 'UTC', 'https://legacy.example.org/events/duplicate', true),
    (:'sharedPathEventID', :'activeEventCategoryID', 'virtual', :'activeGroupID', 'Shared Path Event', 'shared-path-event', 'A published event sharing a path with a group', 'UTC', 'https://legacy.example.org/shared-path', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all unique normalized redirect mappings ordered by legacy path
select is(
    (
        select jsonb_agg(row_to_json(r) order by r.legacy_path)
        from list_redirects() r
    ),
    '[
        {"legacy_path": "/", "new_path": "/active-community/group/root-group"},
        {"legacy_path": "/events/active", "new_path": "/active-community/group/active-group/event/active-event"},
        {"legacy_path": "/events/active-slash", "new_path": "/active-community/group/active-group/event/active-event-slash"},
        {"legacy_path": "/groups/active", "new_path": "/active-community/group/active-group"},
        {"legacy_path": "/groups/active-slash", "new_path": "/active-community/group/active-group-slash"}
    ]'::jsonb,
    'Should return all unique normalized redirect mappings ordered by legacy path'
);

-- Should return canonical relative paths without the base URL prefix
select is(
    (
        select new_path
        from list_redirects()
        where legacy_path = '/groups/active'
    ),
    '/active-community/group/active-group',
    'Should return canonical relative paths without the base URL prefix'
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

-- Should exclude inactive and null legacy URL records
select ok(
    not exists(
        select 1
        from list_redirects()
        where legacy_path in ('/inactive-group', '/events/active-event-null-legacy')
    ),
    'Should exclude inactive and null legacy URL records'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
