insert into notification_kind (notification_kind_id, name, optional_notification)
values ('6bc2dc91-ccff-49f5-8b73-3a70af0387a6', 'site-onboarding', false)
on conflict (name) do update
set optional_notification = excluded.optional_notification;
