-- Tests enqueueing and tracking custom notifications atomically.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '8a070000-0000-0000-0000-000000000001'
\set communityRecipientID '8a070000-0000-0000-0000-000000000007'
\set eventCategoryID '8a070000-0000-0000-0000-000000000008'
\set eventID '8a070000-0000-0000-0000-000000000009'
\set eventRecipientID '8a070000-0000-0000-0000-000000000010'
\set groupCategoryID '8a070000-0000-0000-0000-000000000002'
\set groupID '8a070000-0000-0000-0000-000000000003'
\set mutedRecipientID '8a070000-0000-0000-0000-000000000006'
\set recipientID '8a070000-0000-0000-0000-000000000005'
\set senderID '8a070000-0000-0000-0000-000000000004'
\set trackingFailureRecipientID '8a070000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the custom notifications
select fx_community(:'communityID');

-- User who receives the community custom notification
select fx_user(:'communityRecipientID');

-- User who receives the event custom notification
select fx_user(:'eventRecipientID');

-- User who muted the group named by the custom notification
select fx_user(:'mutedRecipientID', jsonb_build_object('username', 'muted-recipient-enqueue-tracked'));

-- User who receives the baseline custom notification
select fx_user(:'recipientID', jsonb_build_object('username', 'recipient-enqueue-tracked-custom-notification'));

-- User who sends the custom notifications
select fx_user(:'senderID', jsonb_build_object('username', 'sender'));

-- User addressed by the notification whose tracking fails
select fx_user(:'trackingFailureRecipientID');

-- Event category of the event notification
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category of the notified group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group named by the group and event notifications
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event of the event notification
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Mute used to prove enqueue filtering does not block tracking
insert into user_group_notification_mute (group_id, user_id)
values (:'groupID', :'mutedRecipientID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should enqueue and track a custom notification atomically
select lives_ok(
    format(
        $$select enqueue_tracked_custom_notification(
            'group-custom',
            jsonb_build_object('subject', 'Group update'),
            '[]'::jsonb,
            array[%L::uuid],
            %L::uuid,
            %L::uuid,
            null::uuid,
            %L::uuid,
            1,
            'Group update',
            'Body for group notification'
        )$$,
        :'recipientID',
        :'senderID',
        :'communityID',
        :'groupID'
    ),
    'Should enqueue and track a custom notification atomically'
);

-- Should create one notification row
select is(
    (select count(*) from notification where kind = 'group-custom'),
    1::bigint,
    'Should create one notification row'
);

-- Should create one custom notification row
select is(
    (select count(*) from custom_notification where subject = 'Group update'),
    1::bigint,
    'Should create one custom notification row'
);

-- Should enqueue and track a community custom notification without group scope
select lives_ok(
    format(
        $$select enqueue_tracked_custom_notification(
            'community-custom',
            jsonb_build_object('subject', 'Community update enqueue tracked'),
            '[]'::jsonb,
            array[%L::uuid],
            %L::uuid,
            %L::uuid,
            null::uuid,
            null::uuid,
            1,
            'Community update enqueue tracked',
            'Body for community notification',
            '{"roles": ["admin"]}'::jsonb
        )$$,
        :'communityRecipientID',
        :'senderID',
        :'communityID'
    ),
    'Should enqueue and track a community custom notification without group scope'
);

-- Should queue and track the community custom notification
select results_eq(
    format(
        $$
        select
            (
                select user_id
                from notification
                where kind = 'community-custom'
            ),
            (
                select community_id
                from custom_notification
                where subject = 'Community update enqueue tracked'
            ),
            (
                select actor_user_id
                from audit_log
                where action = 'community_custom_notification_sent'
                and community_id = %L::uuid
            ),
            (
                select details->'roles'
                from audit_log
                where action = 'community_custom_notification_sent'
                and community_id = %L::uuid
            )
        $$,
        :'communityID',
        :'communityID'
    ),
    format(
        $$ values (%L::uuid, %L::uuid, %L::uuid, '["Admin"]'::jsonb) $$,
        :'communityRecipientID',
        :'communityID',
        :'senderID'
    ),
    'Should queue and track the community custom notification'
);

-- Should enqueue and track an event custom notification
select lives_ok(
    format(
        $$select enqueue_tracked_custom_notification(
            'event-custom',
            jsonb_build_object('subject', 'Event update enqueue tracked'),
            '[]'::jsonb,
            array[%L::uuid],
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            1,
            'Event update enqueue tracked',
            'Body for event notification'
        )$$,
        :'eventRecipientID',
        :'senderID',
        :'communityID',
        :'eventID',
        :'groupID'
    ),
    'Should enqueue and track an event custom notification'
);

-- Should queue and track the event custom notification in the event scope
select results_eq(
    $$
        select
            (
                select user_id
                from notification
                where kind = 'event-custom'
            ),
            (
                select event_id
                from custom_notification
                where subject = 'Event update enqueue tracked'
            )
    $$,
    format(
        $$ values (%L::uuid, %L::uuid) $$,
        :'eventRecipientID',
        :'eventID'
    ),
    'Should queue and track the event custom notification in the event scope'
);

-- Should track a custom notification even when every recipient is filtered
select lives_ok(
    format(
        $$select enqueue_tracked_custom_notification(
            'group-custom',
            jsonb_build_object('subject', 'Muted group update'),
            '[]'::jsonb,
            array[%L::uuid],
            %L::uuid,
            %L::uuid,
            null::uuid,
            %L::uuid,
            1,
            'Muted group update',
            'Body for muted group notification'
        )$$,
        :'mutedRecipientID',
        :'senderID',
        :'communityID',
        :'groupID'
    ),
    'Should track a custom notification even when every recipient is filtered'
);

-- Should filter muted recipients while keeping the tracking row
select results_eq(
    format(
        $$
        select
            exists (
                select 1
                from notification
                where user_id = %L::uuid
            ),
            (
                select group_id
                from custom_notification
                where subject = 'Muted group update'
            )
        $$,
        :'mutedRecipientID'
    ),
    format(
        $$ values (false, %L::uuid) $$,
        :'groupID'
    ),
    'Should filter muted recipients while keeping the tracking row'
);

-- Should create audit rows for successful tracking operations
select results_eq(
    format(
        $$
        select
            actor_user_id,
            details->>'subject'
        from audit_log
        where action = 'group_custom_notification_sent'
        and group_id = %L::uuid
        order by 2
        $$,
        :'groupID'
    ),
    format(
        $$ values
            (%L::uuid, 'Group update'::text),
            (%L::uuid, 'Muted group update'::text)
        $$,
        :'senderID',
        :'senderID'
    ),
    'Should create audit rows for successful tracking operations'
);

-- Should roll back tracking when enqueue fails
select throws_ok(
    format(
        $$select enqueue_tracked_custom_notification(
            'missing-kind',
            '{}'::jsonb,
            '[]'::jsonb,
            array[%L::uuid],
            %L::uuid,
            %L::uuid,
            null::uuid,
            %L::uuid,
            1,
            'Rolled back',
            'This should not be tracked'
        )$$,
        :'recipientID',
        :'senderID',
        :'communityID',
        :'groupID'
    ),
    '23503',
    null,
    'Should roll back tracking when enqueue fails'
);

-- Should roll back queued notifications when tracking fails
select throws_ok(
    format(
        $$select enqueue_tracked_custom_notification(
            'group-custom',
            jsonb_build_object('subject', 'Tracking failure enqueue tracked'),
            '[]'::jsonb,
            array[%L::uuid],
            %L::uuid,
            %L::uuid,
            null::uuid,
            %L::uuid,
            1,
            'Tracking failure enqueue tracked',
            ' '
        )$$,
        :'trackingFailureRecipientID',
        :'senderID',
        :'communityID',
        :'groupID'
    ),
    '23514',
    null,
    'Should roll back queued notifications when tracking fails'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
