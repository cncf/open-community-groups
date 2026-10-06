-- Tests tracking sent custom notifications and their audit rows.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

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

-- Community owning the tracked custom notifications
select fx_community(:'communityID');

-- User who sends the custom notifications
select fx_user(:'userID', jsonb_build_object('username', 'user-track-custom-notification'));

-- Event category of the event notification
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category named by the community notification filters
select fx_group_category(:'groupCategoryID', :'communityID', jsonb_build_object('name', 'Platform Teams'));

-- Group of the event and group notifications
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event of the event notification
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should store the community custom notification
select lives_ok(
    format(
        $$select track_custom_notification(
            %L::uuid,
            %L::uuid,
            null::uuid,
            null::uuid,
            5,
            'Community update',
            'Body for community notification',
            jsonb_build_object(
                'group_category_ids', jsonb_build_array(%L),
                'roles', jsonb_build_array('admin')
            )
        )$$,
        :'userID',
        :'communityID',
        :'groupCategoryID'
    ),
    'Should store the community custom notification'
);

-- Should persist the community custom notification row
select results_eq(
    $$
        select
            body,
            community_id,
            created_by,
            event_id,
            group_id,
            subject
        from custom_notification
        where subject = 'Community update'
    $$,
    format(
        $$
        values (
            'Body for community notification',
            %L::uuid,
            %L::uuid,
            null::uuid,
            null::uuid,
            'Community update'
        )
        $$,
        :'communityID',
        :'userID'
    ),
    'Should persist the community custom notification row'
);

-- Should create the expected audit row for the community notification
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            event_id,
            resource_type,
            resource_id,
            details
        from audit_log
        where action = 'community_custom_notification_sent'
    $$,
    format(
        $$
        values (
            'community_custom_notification_sent',
            %L::uuid,
            'user-track-custom-notification',
            %L::uuid,
            null::uuid,
            null::uuid,
            'community',
            %L::uuid,
            jsonb_build_object(
                'group_categories', jsonb_build_array('Platform Teams'),
                'recipient_count', 5,
                'regions', 'All',
                'roles', jsonb_build_array('Admin'),
                'subject', 'Community update'
            )
        )
        $$,
        :'userID',
        :'communityID',
        :'communityID'
    ),
    'Should create the expected audit row for the community notification'
);

-- Should store the event custom notification
select lives_ok(
    format(
        $$select track_custom_notification(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            12,
            'Event update',
            'Body for event notification',
            null::jsonb
        )$$,
        :'userID',
        :'communityID',
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
            community_id,
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
            null::uuid,
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
            community_id,
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
            'user-track-custom-notification',
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'event',
            %L::uuid,
            jsonb_build_object('recipient_count', 12, 'subject', 'Event update')
        )
        $$,
        :'userID',
        :'communityID',
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
            %L::uuid,
            null::uuid,
            %L::uuid,
            8,
            'Group update',
            'Body for group notification',
            null::jsonb
        )$$,
        :'userID',
        :'communityID',
        :'groupID'
    ),
    'Should store the group custom notification'
);

-- Should persist the group custom notification row
select results_eq(
    $$
        select
            body,
            community_id,
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
            null::uuid,
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
            community_id,
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
            'user-track-custom-notification',
            %L::uuid,
            %L::uuid,
            null::uuid,
            'group',
            %L::uuid,
            jsonb_build_object('recipient_count', 8, 'subject', 'Group update')
        )
        $$,
        :'userID',
        :'communityID',
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
