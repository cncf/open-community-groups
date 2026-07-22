-- Drop stale functions replaced during notification enqueue cleanup.
drop function if exists activate_pre_registered_user_email_password(jsonb);
drop function if exists cancel_event(uuid, uuid, uuid, text);
drop function if exists cancel_event_series_events(uuid, uuid, uuid[], text);
drop function if exists sign_up_user(jsonb, boolean);
drop function if exists update_event(uuid, uuid, uuid, jsonb, jsonb, text);
