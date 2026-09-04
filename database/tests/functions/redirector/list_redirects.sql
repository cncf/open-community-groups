-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCommunityID '0c010000-0000-0000-0000-000000000001'
\set activeEventCategoryID '0c010000-0000-0000-0000-000000000002'
\set activeEventID '0c010000-0000-0000-0000-000000000003'
\set activeEventNullLegacyID '0c010000-0000-0000-0000-000000000004'
\set activeEventSlashID '0c010000-0000-0000-0000-000000000005'
\set activeGroupCategoryID '0c010000-0000-0000-0000-000000000006'
\set activeGroupID '0c010000-0000-0000-0000-000000000007'
\set activeGroupNullLegacyID '0c010000-0000-0000-0000-000000000008'
\set activeGroupSlashID '0c010000-0000-0000-0000-000000000009'
\set deletedEventID '0c010000-0000-0000-0000-00000000000a'
\set deletedGroupID '0c010000-0000-0000-0000-00000000000b'
\set duplicateCommunityID '0c010000-0000-0000-0000-00000000000c'
\set duplicateEventCategoryID '0c010000-0000-0000-0000-00000000000d'
\set duplicateEventID '0c010000-0000-0000-0000-00000000000e'
\set duplicateEventOnlyID '0c010000-0000-0000-0000-00000000000f'
\set duplicateGroupCategoryID '0c010000-0000-0000-0000-000000000010'
\set duplicateGroupID '0c010000-0000-0000-0000-000000000011'
\set duplicateGroupOnlyID '0c010000-0000-0000-0000-000000000012'
\set inactiveCommunityID '0c010000-0000-0000-0000-000000000013'
\set inactiveGroupCategoryID '0c010000-0000-0000-0000-000000000014'
\set inactiveGroupID '0c010000-0000-0000-0000-000000000015'
\set rootGroupID '0c010000-0000-0000-0000-000000000016'
\set scopedDuplicateGroupID '0c010000-0000-0000-0000-000000000017'
\set sharedPathEventID '0c010000-0000-0000-0000-000000000018'
\set sharedPathGroupID '0c010000-0000-0000-0000-000000000019'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
select fx_community(:'activeCommunityID', jsonb_build_object('name', 'active-community-list-redirects'));
select fx_community(:'duplicateCommunityID', jsonb_build_object('name', 'duplicate-community'));
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

-- Baseline group categories, event categories and groups
select fx_group_category(:'activeGroupCategoryID', :'activeCommunityID');
select fx_group_category(:'duplicateGroupCategoryID', :'duplicateCommunityID');
select fx_group_category(:'inactiveGroupCategoryID', :'inactiveCommunityID');
select fx_event_category(:'activeEventCategoryID', :'activeCommunityID');
select fx_event_category(:'duplicateEventCategoryID', :'duplicateCommunityID');
select fx_group(:'activeGroupNullLegacyID', :'activeCommunityID', :'activeGroupCategoryID');

-- Groups
select fx_group(:'activeGroupID', :'activeCommunityID', :'activeGroupCategoryID', jsonb_build_object(
    'legacy_url', 'https://legacy.example.org/groups/active?source=legacy',
    'slug', 'active-group',
    'slug_pretty', 'active-pretty'
));
select fx_group(:'activeGroupSlashID', :'activeCommunityID', :'activeGroupCategoryID', jsonb_build_object(
    'legacy_url', 'https://legacy.example.org/groups/active-slash/',
    'slug', 'active-group-slash'
));
select fx_group(:'deletedGroupID', :'activeCommunityID', :'activeGroupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true,
    'legacy_url', 'https://legacy.example.org/deleted-group',
    'slug', 'deleted-group'
));
select fx_group(:'duplicateGroupID', :'duplicateCommunityID', :'duplicateGroupCategoryID', jsonb_build_object(
    'legacy_url', 'https://legacy.example.org/group-duplicate',
    'slug', 'duplicate-group'
));
select fx_group(:'duplicateGroupOnlyID', :'duplicateCommunityID', :'duplicateGroupCategoryID', jsonb_build_object('legacy_url', 'https://legacy.example.org/group-duplicate'));
select fx_group(:'inactiveGroupID', :'inactiveCommunityID', :'inactiveGroupCategoryID', jsonb_build_object(
    'legacy_url', 'https://legacy.example.org/inactive-group',
    'slug', 'inactive-group'
));
select fx_group(:'rootGroupID', :'activeCommunityID', :'activeGroupCategoryID', jsonb_build_object(
    'legacy_url', 'https://legacy.example.org',
    'slug', 'root-group'
));
select fx_group(:'scopedDuplicateGroupID', :'duplicateCommunityID', :'duplicateGroupCategoryID', jsonb_build_object(
    'legacy_url', 'https://legacy-duplicate.example.org/groups/active',
    'slug', 'scoped-duplicate-group'
));
select fx_group(:'sharedPathGroupID', :'activeCommunityID', :'activeGroupCategoryID', jsonb_build_object('legacy_url', 'https://legacy.example.org/shared-path'));

-- Events
select fx_event(:'activeEventID', :'activeGroupID', :'activeEventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'legacy_url', 'https://legacy.example.org/events/active?ref=legacy',
    'published', true,
    'slug', 'active-event'
));
select fx_event(:'activeEventSlashID', :'activeGroupID', :'activeEventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'legacy_url', 'https://legacy.example.org/events/active-slash/',
    'published', true,
    'slug', 'active-event-slash'
));
select fx_event(:'activeEventNullLegacyID', :'activeGroupID', :'activeEventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'slug', 'active-event-null-legacy'
));
select fx_event(:'deletedEventID', :'activeGroupID', :'activeEventCategoryID', jsonb_build_object(
    'deleted', true,
    'event_kind_id', 'virtual',
    'legacy_url', 'https://legacy.example.org/events/deleted'
));
select fx_event(:'duplicateEventID', :'duplicateGroupID', :'duplicateEventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'legacy_url', 'https://legacy.example.org/events/duplicate',
    'published', true
));
select fx_event(:'duplicateEventOnlyID', :'duplicateGroupID', :'duplicateEventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'legacy_url', 'https://legacy.example.org/events/duplicate',
    'published', true
));
select fx_event(:'sharedPathEventID', :'activeGroupID', :'activeEventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'legacy_url', 'https://legacy.example.org/shared-path',
    'published', true
));

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
        {"community_name": "active-community-list-redirects", "legacy_path": "/", "new_path": "/active-community-list-redirects/group/root-group"},
        {"community_name": "active-community-list-redirects", "legacy_path": "/events/active", "new_path": "/active-community-list-redirects/group/active-group/event/active-event"},
        {"community_name": "active-community-list-redirects", "legacy_path": "/events/active-slash", "new_path": "/active-community-list-redirects/group/active-group/event/active-event-slash"},
        {"community_name": "active-community-list-redirects", "legacy_path": "/groups/active", "new_path": "/active-community-list-redirects/group/active-group"},
        {"community_name": "active-community-list-redirects", "legacy_path": "/groups/active-slash", "new_path": "/active-community-list-redirects/group/active-group-slash"},
        {"community_name": "duplicate-community", "legacy_path": "/groups/active", "new_path": "/duplicate-community/group/scoped-duplicate-group"}
    ]'::jsonb,
    'Should return all unique normalized redirect mappings ordered by legacy path'
);

-- Should return canonical relative paths without the base URL prefix
select is(
    (
        select new_path
        from list_redirects()
        where community_name = 'active-community-list-redirects'
          and legacy_path = '/groups/active'
    ),
    '/active-community-list-redirects/group/active-group',
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
        {"community_name": "active-community-list-redirects", "legacy_path": "/groups/active", "new_path": "/active-community-list-redirects/group/active-group"},
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
