-- Drops the event mutation and capacity validation functions so they can be recreated with meeting provider limits.

drop function if exists add_event(uuid, uuid, jsonb, jsonb, text);
drop function if exists add_event_series(uuid, uuid, jsonb, jsonb, jsonb, text);
drop function if exists update_event(uuid, uuid, uuid, jsonb, jsonb, text);
drop function if exists validate_event_capacity(jsonb, jsonb, uuid, int);
