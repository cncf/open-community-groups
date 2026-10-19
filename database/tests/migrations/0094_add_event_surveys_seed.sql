-- Seeds schema-93 notification opt-outs for the event surveys upgrade test.

begin;

\set bothOptedOutUserID '94000000-0000-0000-0000-000000000003'
\set noOptOutsUserID '94000000-0000-0000-0000-000000000004'
\set otherOptedOutUserID '94000000-0000-0000-0000-000000000002'
\set remindersOptedOutUserID '94000000-0000-0000-0000-000000000001'

-- User who turned event reminders and badges off
insert into "user" (auth_hash, email, user_id, username)
values (
    'hash',
    'event-surveys-both-opted-out@example.test',
    :'bothOptedOutUserID',
    'event-surveys-both-opted-out'
);

-- User who kept every category on
insert into "user" (auth_hash, email, user_id, username)
values (
    'hash',
    'event-surveys-no-opt-outs@example.test',
    :'noOptOutsUserID',
    'event-surveys-no-opt-outs'
);

-- User who kept event reminders on and turned badges off
insert into "user" (auth_hash, email, user_id, username)
values (
    'hash',
    'event-surveys-other-opted-out@example.test',
    :'otherOptedOutUserID',
    'event-surveys-other-opted-out'
);

-- User who turned event reminders off and kept other categories on
insert into "user" (auth_hash, email, user_id, username)
values (
    'hash',
    'event-surveys-reminders-opted-out@example.test',
    :'remindersOptedOutUserID',
    'event-surveys-reminders-opted-out'
);

-- Badges opt-out of the user who turned both categories off
insert into user_notification_opt_out (notification_category_id, user_id)
values ('badges', :'bothOptedOutUserID');

-- Event reminders opt-out of the user who turned both categories off
insert into user_notification_opt_out (notification_category_id, user_id)
values ('event-reminders', :'bothOptedOutUserID');

-- Badges opt-out that does not affect the event surveys category
insert into user_notification_opt_out (notification_category_id, user_id)
values ('badges', :'otherOptedOutUserID');

-- Event reminders opt-out inherited by the event surveys category
insert into user_notification_opt_out (notification_category_id, user_id)
values ('event-reminders', :'remindersOptedOutUserID');

commit;
