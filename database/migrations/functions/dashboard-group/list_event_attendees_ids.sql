-- Returns all verified attendees user ids for the given event.
create or replace function list_event_attendees_ids(p_event_id uuid)
returns json as $$
    select coalesce(json_agg(attendee.user_id), '[]'::json)
    from (
        select ea.user_id
        from event_attendee ea
        join "user" u using (user_id)
        where ea.event_id = p_event_id
        and u.email_verified = true
        order by ea.user_id asc
    ) attendee;
$$ language sql;

