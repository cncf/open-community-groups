-- Add event-level reminder settings and event reminder notification kind.
alter table event
    add column event_reminder_enabled boolean not null default true,
    add column event_reminder_evaluated_for_starts_at timestamptz,
    add column event_reminder_sent_at timestamptz;

insert into notification_kind (name) values ('event-reminder');
