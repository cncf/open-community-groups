-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000021'
\set userID '00000000-0000-0000-0000-000000000041'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'Meetup', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'Test Group', 'test-group');

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

-- User
insert into "user" (auth_hash, email, email_verified, user_id, username)
values (gen_random_bytes(32), 'user@example.com', true, :'userID', 'user');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should store the event custom notification
select lives_ok(
    $$select track_custom_notification(
        '00000000-0000-0000-0000-000000000041'::uuid,
        '00000000-0000-0000-0000-000000000031'::uuid,
        '00000000-0000-0000-0000-000000000021'::uuid,
        12,
        'Event update',
        'Body for event notification'
    )$$,
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
    $$
        values (
            'Body for event notification',
            '00000000-0000-0000-0000-000000000041'::uuid,
            '00000000-0000-0000-0000-000000000031'::uuid,
            null::uuid,
            'Event update'
        )
    $$,
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
    $$
        values (
            'event_custom_notification_sent',
            '00000000-0000-0000-0000-000000000041'::uuid,
            'user',
            '00000000-0000-0000-0000-000000000021'::uuid,
            '00000000-0000-0000-0000-000000000031'::uuid,
            'event',
            '00000000-0000-0000-0000-000000000031'::uuid,
            jsonb_build_object('recipient_count', 12, 'subject', 'Event update')
        )
    $$,
    'Should create the expected audit row for the event notification'
);

-- Should store the group custom notification
select lives_ok(
    $$select track_custom_notification(
        '00000000-0000-0000-0000-000000000041'::uuid,
        null::uuid,
        '00000000-0000-0000-0000-000000000021'::uuid,
        8,
        'Group update',
        'Body for group notification'
    )$$,
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
    $$
        values (
            'Body for group notification',
            '00000000-0000-0000-0000-000000000041'::uuid,
            null::uuid,
            '00000000-0000-0000-0000-000000000021'::uuid,
            'Group update'
        )
    $$,
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
    $$
        values (
            'group_custom_notification_sent',
            '00000000-0000-0000-0000-000000000041'::uuid,
            'user',
            '00000000-0000-0000-0000-000000000021'::uuid,
            null::uuid,
            'group',
            '00000000-0000-0000-0000-000000000021'::uuid,
            jsonb_build_object('recipient_count', 8, 'subject', 'Group update')
        )
    $$,
    'Should create the expected audit row for the group notification'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
