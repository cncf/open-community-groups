-- Adds required paid-event admin notifications and updates the event mutation contract.

insert into notification_kind (name, optional_notification)
values ('event-paid-configured', false);

drop function if exists update_event(uuid, uuid, uuid, jsonb, jsonb, text);
