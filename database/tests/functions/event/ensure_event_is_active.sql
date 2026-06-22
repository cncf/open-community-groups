-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance2ID '5e040000-0000-0000-0000-000000000001'
\set allianceID '5e040000-0000-0000-0000-000000000002'
\set eventCanceledID '5e040000-0000-0000-0000-000000000003'
\set eventCategoryID '5e040000-0000-0000-0000-000000000004'
\set eventDeletedID '5e040000-0000-0000-0000-000000000005'
\set eventInactiveGroupID '5e040000-0000-0000-0000-000000000006'
\set eventOKID '5e040000-0000-0000-0000-000000000007'
\set eventPastID '5e040000-0000-0000-0000-000000000008'
\set eventUnpublishedID '5e040000-0000-0000-0000-000000000009'
\set groupCategoryID '5e040000-0000-0000-0000-00000000000a'
\set groupID '5e040000-0000-0000-0000-00000000000b'
\set inactiveGroupID '5e040000-0000-0000-0000-00000000000c'
\set missingEventID '5e040000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliances
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'event-alliance',
    'Event Alliance',
    'Test alliance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
), (
    :'alliance2ID',
    'other-event-alliance',
    'Other Event Alliance',
    'Other test alliance',
    'https://example.com/banner-mobile-2.png',
    'https://example.com/banner-2.png',
    'https://example.com/logo-2.png'
);

-- Group category
insert into group_category (
    group_category_id,
    alliance_id,
    name
) values (
    :'groupCategoryID',
    :'allianceID',
    'Technology'
);

-- Event category
insert into event_category (
    event_category_id,
    alliance_id,
    name
) values (
    :'eventCategoryID',
    :'allianceID',
    'General'
);

-- Groups
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Active Group',
    'active-group',
    true,
    false
), (
    :'inactiveGroupID',
    :'allianceID',
    :'groupCategoryID',
    'Inactive Group',
    'inactive-group',
    false,
    false
);

-- Events
insert into event (
    canceled,
    deleted,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    false,
    false,
    'Active event',
    :'eventCategoryID',
    :'eventOKID',
    'in-person',
    :'groupID',
    'Active Event',
    true,
    'active-event',
    current_timestamp + interval '1 day',
    'UTC'
), (
    true,
    false,
    'Canceled event',
    :'eventCategoryID',
    :'eventCanceledID',
    'in-person',
    :'groupID',
    'Canceled Event',
    false,
    'canceled-event',
    current_timestamp + interval '1 day',
    'UTC'
), (
    false,
    true,
    'Deleted event',
    :'eventCategoryID',
    :'eventDeletedID',
    'in-person',
    :'groupID',
    'Deleted Event',
    false,
    'deleted-event',
    current_timestamp + interval '1 day',
    'UTC'
), (
    false,
    false,
    'Inactive group event',
    :'eventCategoryID',
    :'eventInactiveGroupID',
    'in-person',
    :'inactiveGroupID',
    'Inactive Group Event',
    true,
    'inactive-group-event',
    current_timestamp + interval '1 day',
    'UTC'
), (
    false,
    false,
    'Past event',
    :'eventCategoryID',
    :'eventPastID',
    'in-person',
    :'groupID',
    'Past Event',
    true,
    'past-event',
    current_timestamp - interval '2 days',
    'UTC'
), (
    false,
    false,
    'Unpublished event',
    :'eventCategoryID',
    :'eventUnpublishedID',
    'in-person',
    :'groupID',
    'Unpublished Event',
    false,
    'unpublished-event',
    current_timestamp + interval '1 day',
    'UTC'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept active event
select lives_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'allianceID', :'eventOKID'
    ),
    'Should accept active event'
);

-- Should reject missing event
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'allianceID', :'missingEventID'
    ),
    'event not found or inactive',
    'Should reject missing event'
);

-- Should reject event from another alliance
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'alliance2ID', :'eventOKID'
    ),
    'event not found or inactive',
    'Should reject event from another alliance'
);

-- Should reject unpublished event
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'allianceID', :'eventUnpublishedID'
    ),
    'event not found or inactive',
    'Should reject unpublished event'
);

-- Should reject canceled event
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'allianceID', :'eventCanceledID'
    ),
    'event not found or inactive',
    'Should reject canceled event'
);

-- Should reject deleted event
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'allianceID', :'eventDeletedID'
    ),
    'event not found or inactive',
    'Should reject deleted event'
);

-- Should reject inactive-group event
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'allianceID', :'eventInactiveGroupID'
    ),
    'event not found or inactive',
    'Should reject inactive-group event'
);

-- Should reject past event
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'allianceID', :'eventPastID'
    ),
    'event not found or inactive',
    'Should reject past event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
