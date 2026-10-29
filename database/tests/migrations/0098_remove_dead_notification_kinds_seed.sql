-- Seeds schema-97 notifications of removed and kept kinds for the dead notification kinds removal test.

begin;

\set attachmentID '98000000-0000-0000-0000-000000000002'
\set controlNotificationID '98000000-0000-0000-0000-000000000005'
\set invitationNotificationID '98000000-0000-0000-0000-000000000004'
\set promotedNotificationID '98000000-0000-0000-0000-000000000003'
\set userID '98000000-0000-0000-0000-000000000001'

-- Recipient of every notification
insert into "user" (
    auth_hash,
    email,
    user_id,
    username
) values (
    'hash',
    'dead-notification-kinds@example.test',
    :'userID',
    'dead-notification-kinds'
);

-- Calendar attachment shared by a removed-kind and a kept-kind notification
insert into attachment (
    attachment_id,
    content_type,
    data,
    file_name,
    hash
) values (
    :'attachmentID',
    'text/calendar',
    convert_to('BEGIN:VCALENDAR', 'UTF8'),
    'event.ics',
    'dead-notification-kinds-attachment'
);

-- Notifications of the removed kinds and a kept control kind
insert into notification (
    kind,
    notification_id,
    user_id
) values
    ('event-invitation', :'invitationNotificationID', :'userID'),
    ('event-waitlist-joined', :'controlNotificationID', :'userID'),
    ('event-waitlist-promoted', :'promotedNotificationID', :'userID');

-- Attachment links of the removed-kind and control notifications
insert into notification_attachment (
    attachment_id,
    notification_id
) values
    (:'attachmentID', :'controlNotificationID'),
    (:'attachmentID', :'promotedNotificationID');

commit;
