-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '8a050000-0000-0000-0000-000000000001'
\set eventCategoryID '8a050000-0000-0000-0000-000000000002'
\set eventID '8a050000-0000-0000-0000-000000000003'
\set groupCategoryID '8a050000-0000-0000-0000-000000000004'
\set groupID '8a050000-0000-0000-0000-000000000005'
\set userID '8a050000-0000-0000-0000-000000000006'

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
    'custom-notification-community',
    'Custom Notification Community',
    'Community used for custom notification tests',
    'https://example.com/custom-notification-banner-mobile.png',
    'https://example.com/custom-notification-banner.png',
    'https://example.com/custom-notification-logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', gen_random_bytes(32), 'user@example.com', true, 'user');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Event
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    'Test event',
    :'eventCategoryID',
    :'eventID',
    'virtual',
    :'groupID',
    'Test Event',
    'test-event',
    'UTC'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should store the event custom notification
select lives_ok(
    format(
        $$select track_custom_notification(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        12,
        'Event update',
        'Body for event notification'
        )$$,
        :'userID',
        :'eventID',
        :'groupID'
    ),
    'Should store the event custom notification'
);

-- Should persist the event custom notification row
select results_eq(
    $$
        select
            body,
            created_by,
            event_id,
            group_id,
            subject
        from custom_notification
        where subject = 'Event update'
    $$,
    format(
        $$
        values (
            'Body for event notification',
            %L::uuid,
            %L::uuid,
            null::uuid,
            'Event update'
        )
        $$,
        :'userID',
        :'eventID'
    ),
    'Should persist the event custom notification row'
);

-- Should create the expected audit row for the event notification
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            group_id,
            event_id,
            resource_type,
            resource_id,
            details
        from audit_log
        where action = 'event_custom_notification_sent'
    $$,
    format(
        $$
        values (
            'event_custom_notification_sent',
            %L::uuid,
            'user',
            %L::uuid,
            %L::uuid,
            'event',
            %L::uuid,
            jsonb_build_object('recipient_count', 12, 'subject', 'Event update')
        )
        $$,
        :'userID',
        :'groupID',
        :'eventID',
        :'eventID'
    ),
    'Should create the expected audit row for the event notification'
);

-- Should store the group custom notification
select lives_ok(
    format(
        $$select track_custom_notification(
        %L::uuid,
        null::uuid,
        %L::uuid,
        8,
        'Group update',
        'Body for group notification'
        )$$,
        :'userID',
        :'groupID'
    ),
    'Should store the group custom notification'
);

-- Should persist the group custom notification row
select results_eq(
    $$
        select
            body,
            created_by,
            event_id,
            group_id,
            subject
        from custom_notification
        where subject = 'Group update'
    $$,
    format(
        $$
        values (
            'Body for group notification',
            %L::uuid,
            null::uuid,
            %L::uuid,
            'Group update'
        )
        $$,
        :'userID',
        :'groupID'
    ),
    'Should persist the group custom notification row'
);

-- Should create the expected audit row for the group notification
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            group_id,
            event_id,
            resource_type,
            resource_id,
            details
        from audit_log
        where action = 'group_custom_notification_sent'
    $$,
    format(
        $$
        values (
            'group_custom_notification_sent',
            %L::uuid,
            'user',
            %L::uuid,
            null::uuid,
            'group',
            %L::uuid,
            jsonb_build_object('recipient_count', 8, 'subject', 'Group update')
        )
        $$,
        :'userID',
        :'groupID',
        :'groupID'
    ),
    'Should create the expected audit row for the group notification'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
