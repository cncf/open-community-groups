-- Drop the inbox event visibility helper replaced by is_event_public.

drop function if exists is_inbox_event_public(event, "group");
