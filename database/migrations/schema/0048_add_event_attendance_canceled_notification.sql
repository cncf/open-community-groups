-- Add notification kind for attendance cancellation confirmations.

insert into notification_kind (name)
values ('event-attendance-canceled')
on conflict (name) do nothing;
