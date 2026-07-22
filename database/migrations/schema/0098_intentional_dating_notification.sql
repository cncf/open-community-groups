insert into notification_kind (name, optional_notification)
values ('intentional-dating-introduction', true)
on conflict (name) do update set optional_notification = excluded.optional_notification;
