-- Returns all verified attendees user ids for the given event.
create or replace function list_event_attendees_ids(p_group_id uuid, p_event_id uuid)
returns uuid[] as $$
    select coalesce(array_agg(ea.user_id order by ea.user_id asc), array[]::uuid[])
    from event_attendee ea
    join "user" u using (user_id)
    join event e using (event_id)
    where ea.event_id = p_event_id
    and e.group_id = p_group_id
    and u.email_verified = true;
$$ language sql;
