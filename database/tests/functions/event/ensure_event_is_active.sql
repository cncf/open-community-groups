-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000061'
\set community2ID '00000000-0000-0000-0000-000000000062'
\set eventCanceledID '00000000-0000-0000-0000-000000000066'
\set eventCategoryID '00000000-0000-0000-0000-000000000063'
\set eventDeletedID '00000000-0000-0000-0000-000000000067'
\set eventInactiveGroupID '00000000-0000-0000-0000-000000000068'
\set eventOKID '00000000-0000-0000-0000-000000000065'
\set eventPastID '00000000-0000-0000-0000-000000000069'
\set eventUnpublishedID '00000000-0000-0000-0000-000000000070'
\set groupCategoryID '00000000-0000-0000-0000-000000000064'
\set groupID '00000000-0000-0000-0000-000000000071'
\set inactiveGroupID '00000000-0000-0000-0000-000000000072'
\set missingEventID '00000000-0000-0000-0000-000000000073'

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
) values (
    :'communityID',
    'event-community',
    'Event Community',
    'Test community',
    'https://example.com/logo.png',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png'
), (
    :'community2ID',
    'other-event-community',
    'Other Event Community',
    'Other test community',
    'https://example.com/logo-2.png',
    'https://example.com/banner-mobile-2.png',
    'https://example.com/banner-2.png'
);

-- Group category
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    :'groupCategoryID',
    :'communityID',
    'Technology'
);

-- Event category
insert into event_category (
    event_category_id,
    community_id,
    name
) values (
    :'eventCategoryID',
    :'communityID',
    'General'
);

-- Groups
insert into "group" (
    active,
    community_id,
    deleted,
    group_category_id,
    group_id,
    name,
    slug
) values (
    true,
    :'communityID',
    false,
    :'groupCategoryID',
    :'groupID',
    'Active Group',
    'active-group'
), (
    false,
    :'communityID',
    false,
    :'groupCategoryID',
    :'inactiveGroupID',
    'Inactive Group',
    'inactive-group'
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
    $$select ensure_event_is_active(
        '00000000-0000-0000-0000-000000000061'::uuid,
        '00000000-0000-0000-0000-000000000065'::uuid
    )$$,
    'Should accept active event'
);

-- Should reject missing event
select throws_ok(
    $$select ensure_event_is_active(
        '00000000-0000-0000-0000-000000000061'::uuid,
        '00000000-0000-0000-0000-000000000073'::uuid
    )$$,
    'event not found or inactive',
    'Should reject missing event'
);

-- Should reject event from another community
select throws_ok(
    $$select ensure_event_is_active(
        '00000000-0000-0000-0000-000000000062'::uuid,
        '00000000-0000-0000-0000-000000000065'::uuid
    )$$,
    'event not found or inactive',
    'Should reject event from another community'
);

-- Should reject unpublished event
select throws_ok(
    $$select ensure_event_is_active(
        '00000000-0000-0000-0000-000000000061'::uuid,
        '00000000-0000-0000-0000-000000000070'::uuid
    )$$,
    'event not found or inactive',
    'Should reject unpublished event'
);

-- Should reject canceled event
select throws_ok(
    $$select ensure_event_is_active(
        '00000000-0000-0000-0000-000000000061'::uuid,
        '00000000-0000-0000-0000-000000000066'::uuid
    )$$,
    'event not found or inactive',
    'Should reject canceled event'
);

-- Should reject deleted event
select throws_ok(
    $$select ensure_event_is_active(
        '00000000-0000-0000-0000-000000000061'::uuid,
        '00000000-0000-0000-0000-000000000067'::uuid
    )$$,
    'event not found or inactive',
    'Should reject deleted event'
);

-- Should reject inactive-group event
select throws_ok(
    $$select ensure_event_is_active(
        '00000000-0000-0000-0000-000000000061'::uuid,
        '00000000-0000-0000-0000-000000000068'::uuid
    )$$,
    'event not found or inactive',
    'Should reject inactive-group event'
);

-- Should reject past event
select throws_ok(
    $$select ensure_event_is_active(
        '00000000-0000-0000-0000-000000000061'::uuid,
        '00000000-0000-0000-0000-000000000069'::uuid
    )$$,
    'event not found or inactive',
    'Should reject past event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
