-- Tests removing the dead notification kinds and their notifications.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attachmentID '98000000-0000-0000-0000-000000000002'
\set controlNotificationID '98000000-0000-0000-0000-000000000005'
\set invitationNotificationID '98000000-0000-0000-0000-000000000004'
\set promotedNotificationID '98000000-0000-0000-0000-000000000003'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should delete the removed notification kinds
select is(
    (
        select count(*)::int
        from notification_kind
        where name in ('event-invitation', 'event-waitlist-promoted')
    ),
    0,
    'Should delete the removed notification kinds'
);

-- Should delete the notifications of the removed kinds
select is(
    (
        select count(*)::int
        from notification
        where notification_id in (
            :'invitationNotificationID'::uuid,
            :'promotedNotificationID'::uuid
        )
    ),
    0,
    'Should delete the notifications of the removed kinds'
);

-- Should delete the attachment links of the removed notifications
select is(
    (
        select count(*)::int
        from notification_attachment
        where notification_id = :'promotedNotificationID'::uuid
    ),
    0,
    'Should delete the attachment links of the removed notifications'
);

-- Should keep notifications of other kinds with their attachments
select results_eq(
    format(
        $$
            select n.kind, na.attachment_id
            from notification n
            join notification_attachment na using (notification_id)
            join attachment a using (attachment_id)
            where n.notification_id = %L::uuid
        $$,
        :'controlNotificationID'
    ),
    format(
        $$ values ('event-waitlist-joined'::text, %L::uuid) $$,
        :'attachmentID'
    ),
    'Should keep notifications of other kinds with their attachments'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
