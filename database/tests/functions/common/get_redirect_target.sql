-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

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
    (:'rootGroupID', :'activeCommunityID', :'activeGroupCategoryID', 'Root Group', 'root-group', 'A group using the site root as legacy URL', 'https://legacy.example.org');

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
    (:'duplicateEventOnlyID', :'duplicateEventCategoryID', 'virtual', :'duplicateGroupID', 'Duplicate Event Only', 'duplicate-event-only', 'Another published event sharing the same legacy URL', 'UTC', 'https://legacy.example.org/events/duplicate', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return group redirect target for a unique group match
select is(
    get_redirect_target('group', '/groups/active')::jsonb,
    '{
        "community_name": "active-community",
        "entity": "group",
        "group_slug": "active-group",
        "event_slug": null
    }'::jsonb,
    'Should return group redirect target for a unique group match'
);

-- Should return event redirect target for a unique event match
select is(
    get_redirect_target('event', '/events/active')::jsonb,
    '{
        "community_name": "active-community",
        "entity": "event",
        "group_slug": "active-group",
        "event_slug": "active-event"
    }'::jsonb,
    'Should return event redirect target for a unique event match'
);

-- Should normalize trailing slashes for unique group matches
select is(
    get_redirect_target('group', '/groups/active-slash')::jsonb,
    '{
        "community_name": "active-community",
        "entity": "group",
        "group_slug": "active-group-slash",
        "event_slug": null
    }'::jsonb,
    'Should normalize trailing slashes for unique group matches'
);

-- Should normalize trailing slashes for unique event matches
select is(
    get_redirect_target('event', '/events/active-slash')::jsonb,
    '{
        "community_name": "active-community",
        "entity": "event",
        "group_slug": "active-group",
        "event_slug": "active-event-slash"
    }'::jsonb,
    'Should normalize trailing slashes for unique event matches'
);

-- Should return null for duplicate group legacy URL matches
select ok(
    get_redirect_target('group', '/group-duplicate') is null,
    'Should return null for duplicate group legacy URL matches'
);

-- Should return null for duplicate event legacy URL matches
select ok(
    get_redirect_target('event', '/events/duplicate') is null,
    'Should return null for duplicate event legacy URL matches'
);

-- Should match root legacy URLs as a slash path
select is(
    get_redirect_target('group', '/')::jsonb,
    '{
        "community_name": "active-community",
        "entity": "group",
        "group_slug": "root-group",
        "event_slug": null
    }'::jsonb,
    'Should match root legacy URLs as a slash path'
);

-- Should ignore null legacy URLs when matching root paths
select is(
    get_redirect_target('event', '/events/active')::jsonb,
    '{
        "community_name": "active-community",
        "entity": "event",
        "group_slug": "active-group",
        "event_slug": "active-event"
    }'::jsonb,
    'Should ignore null legacy URLs when matching event paths'
);

-- Should return null for inactive community matches
select ok(
    get_redirect_target('group', '/inactive-group') is null,
    'Should return null for inactive community matches'
);

-- Should return null for missing legacy URL matches
select ok(
    get_redirect_target('group', '/missing') is null,
    'Should return null for missing legacy URL matches'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
