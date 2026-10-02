-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '8a070000-0000-0000-0000-000000000001'
\set groupCategoryID '8a070000-0000-0000-0000-000000000002'
\set groupID '8a070000-0000-0000-0000-000000000003'
\set mutedRecipientID '8a070000-0000-0000-0000-000000000006'
\set senderID '8a070000-0000-0000-0000-000000000004'
\set recipientID '8a070000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group category and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

select fx_user(:'senderID', jsonb_build_object('username', 'sender'));

-- User who receives the baseline custom notification
select fx_user(:'recipientID', jsonb_build_object('username', 'recipient-enqueue-tracked-custom-notification'));

-- User who muted the group named by the custom notification
select fx_user(:'mutedRecipientID', jsonb_build_object('username', 'muted-recipient-enqueue-tracked'));

-- Mute used to prove enqueue filtering does not block tracking
insert into user_group_notification_mute (group_id, user_id)
values (:'groupID', :'mutedRecipientID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should enqueue and track a custom notification atomically.
select lives_ok(
    format(
        $$select enqueue_tracked_custom_notification(
            'group-custom',
            jsonb_build_object('subject', 'Group update'),
            '[]'::jsonb,
            array[%L::uuid],
            %L::uuid,
            null::uuid,
            %L::uuid,
            1,
            'Group update',
            'Body for group notification'
        )$$,
        :'recipientID',
        :'senderID',
        :'groupID'
    ),
    'Should enqueue and track a custom notification atomically'
);

-- Should create one notification row.
select is(
    (select count(*) from notification where kind = 'group-custom'),
    1::bigint,
    'Should create one notification row'
);

-- Should create one custom notification row.
select is(
    (select count(*) from custom_notification where subject = 'Group update'),
    1::bigint,
    'Should create one custom notification row'
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
            null::uuid,
            %L::uuid,
            1,
            'Muted group update',
            'Body for muted group notification'
        )$$,
        :'mutedRecipientID',
        :'senderID',
        :'groupID'
    ),
    'Should track a custom notification even when every recipient is filtered'
);

-- Should filter muted recipients while keeping the tracking row
select ok(
    not exists (
        select 1
        from notification
        where kind = 'group-custom'
        and user_id = :'mutedRecipientID'
    )
    and exists (
        select 1
        from custom_notification
        where subject = 'Muted group update'
    ),
    'Should filter muted recipients while keeping the tracking row'
);

-- Should create audit rows for successful tracking operations.
select is(
    (select count(*) from audit_log where action = 'group_custom_notification_sent'),
    2::bigint,
    'Should create audit rows for successful tracking operations'
);

-- Should roll back tracking when enqueue fails.
select throws_ok(
    format(
        $$select enqueue_tracked_custom_notification(
            'missing-kind',
            '{}'::jsonb,
            '[]'::jsonb,
            array[%L::uuid],
            %L::uuid,
            null::uuid,
            %L::uuid,
            1,
            'Rolled back',
            'This should not be tracked'
        )$$,
        :'recipientID',
        :'senderID',
        :'groupID'
    ),
    '23503',
    null,
    'Should roll back tracking when enqueue fails'
);

-- Should not track the failed custom notification.
select is(
    (select count(*) from custom_notification where subject = 'Rolled back'),
    0::bigint,
    'Should not track the failed custom notification'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
