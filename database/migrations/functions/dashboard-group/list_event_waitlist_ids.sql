-- Returns all verified waiting list user ids for the given event.
create or replace function list_event_waitlist_ids(p_group_id uuid, p_event_id uuid)
returns uuid[] as $$
    select coalesce(array_agg(ew.user_id order by ew.user_id asc), array[]::uuid[])
    from event_waitlist ew
    join "user" u using (user_id)
    join event e using (event_id)
    where ew.event_id = p_event_id
    and e.group_id = p_group_id
    and u.email_verified = true;
$$ language sql;
