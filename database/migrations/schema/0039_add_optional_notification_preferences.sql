-- Add user preference support for opting out of optional notifications.

alter table "user"
    add column if not exists optional_notifications_enabled boolean not null default true;

alter table notification_kind
    add column if not exists optional_notification boolean not null default false;

update notification_kind
set optional_notification = true
where name in (
    'event-custom',
    'event-published',
    'event-reminder',
    'event-series-published',
    'group-custom'
);
