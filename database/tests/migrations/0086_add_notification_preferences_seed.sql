-- Seeds schema-85 notification preference shapes for the notification preferences upgrade test.

begin;

\set falseUserID '86000000-0000-0000-0000-000000000001'
\set notificationID '86000000-0000-0000-0000-000000000003'
\set trueUserID '86000000-0000-0000-0000-000000000002'

-- User whose disabled optional notification flag should become category opt-outs
insert into "user" (
    auth_hash,
    email,
    optional_notifications_enabled,
    user_id,
    username
) values (
    'hash',
    'notification-preferences-disabled@example.test',
    false,
    :'falseUserID',
    'notification-preferences-disabled'
);

-- User whose enabled optional notification flag should not create opt-outs
insert into "user" (
    auth_hash,
    email,
    optional_notifications_enabled,
    user_id,
    username
) values (
    'hash',
    'notification-preferences-enabled@example.test',
    true,
    :'trueUserID',
    'notification-preferences-enabled'
);

-- Pending notification proving existing notification rows survive the migration
insert into notification (
    kind,
    notification_id,
    user_id
) values (
    'event-canceled',
    :'notificationID',
    :'falseUserID'
);

commit;
