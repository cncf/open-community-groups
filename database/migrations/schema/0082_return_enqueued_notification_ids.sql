-- Drops enqueue_notification so it can be recreated returning the identifiers of the notifications it creates.

drop function if exists enqueue_notification(text, jsonb, jsonb, uuid[]);
