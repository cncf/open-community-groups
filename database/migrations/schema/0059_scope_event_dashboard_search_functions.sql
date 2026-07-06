-- Drops event dashboard search functions before updating their signatures.

drop function if exists search_event_attendees(uuid, jsonb);
drop function if exists search_event_invitation_requests(uuid, jsonb);
drop function if exists search_event_waitlist(uuid, jsonb);
