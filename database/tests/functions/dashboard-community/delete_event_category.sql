-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c090000-0000-0000-0000-000000000001'
\set eventID '2c090000-0000-0000-0000-000000000002'
\set groupCategoryID '2c090000-0000-0000-0000-000000000003'
\set groupID '2c090000-0000-0000-0000-000000000004'
\set inUseEventCategoryID '2c090000-0000-0000-0000-000000000005'
\set unknownEventCategoryID '2c090000-0000-0000-0000-000000000006'
\set unusedEventCategoryID '2c090000-0000-0000-0000-000000000007'

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
    'cncf-seattle',
    'CNCF Seattle',
    'Community for event category delete tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    :'groupCategoryID',
    :'communityID',
    'Platform'
);

-- Event categories
insert into event_category (
    event_category_id,
    community_id,
    name
) values
    (:'inUseEventCategoryID', :'communityID', 'Meetup'),
    (:'unusedEventCategoryID', :'communityID', 'Webinar');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Seattle Platform',
    'seattle-platform'
);

-- Event using the first category
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone
) values (
    :'eventID',
    :'inUseEventCategoryID',
    'in-person',
    :'groupID',
    'Monthly Meetup',
    'monthly-meetup',
    'Test event',
    'UTC'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block deleting category that is still referenced by events
select throws_ok(
    format(
        $$ select delete_event_category(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'inUseEventCategoryID'
    ),
    'cannot delete event category in use by events',
    'Should block deleting event category referenced by events'
);

-- Should delete event category with no event references
select lives_ok(
    format(
        $$ select delete_event_category(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'unusedEventCategoryID'
    ),
    'Should delete an unused event category'
);
select results_eq(
    format(
        $$
    select count(*)::bigint
    from event_category ec
    where ec.event_category_id = %L::uuid
        $$,
        :'unusedEventCategoryID'
    ),
    $$ values (0::bigint) $$,
    'Unused event category should be deleted'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            details,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'event_category_deleted',
            null::uuid,
            null::text,
            %L::uuid,
            '{"name": "Webinar"}'::jsonb,
            'event_category',
            %L::uuid
        )
        $$,
        :'communityID',
        :'unusedEventCategoryID'
    ),
    'Should create the expected audit row'
);

-- Should fail when target category does not exist
select throws_ok(
    format(
        $$ select delete_event_category(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'unknownEventCategoryID'
    ),
    'event category not found',
    'Should fail when deleting a non-existing event category'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
