-- Drop functions whose return types changed from JSON to typed UUID arrays.
drop function if exists list_event_attendees_ids(uuid, uuid);
drop function if exists list_event_waitlist_ids(uuid, uuid);
drop function if exists list_group_members_ids(uuid);
drop function if exists list_group_team_members_ids(uuid);
drop function if exists promote_event_waitlist(uuid, int);
