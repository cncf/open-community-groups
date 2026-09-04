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

-- Baseline community, categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

select fx_user(:'userID', jsonb_build_object('username', 'user-track-custom-notification'));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

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
            'user-track-custom-notification',
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
            'user-track-custom-notification',
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
