insert into meeting_provider (meeting_provider_id, display_name)
values ('google_meet', 'Google Meet')
on conflict do nothing;
