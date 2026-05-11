-- Add user preference support for opting out of mass communications.

alter table "user"
    add column if not exists mass_notifications_enabled boolean not null default true;

alter table notification_kind
    add column if not exists mass_communication boolean not null default false;

update notification_kind
set mass_communication = true
where name in (
    'event-custom',
    'event-published',
    'event-reminder',
    'event-series-published',
    'group-custom'
);
