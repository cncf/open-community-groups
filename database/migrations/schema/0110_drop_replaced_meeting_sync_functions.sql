-- Drops meeting sync functions recreated with additional optional parameters.

drop function if exists release_meeting_sync(uuid, uuid, timestamptz, text, text);
drop function if exists release_meeting_sync_claim(uuid, uuid, uuid, timestamptz);
