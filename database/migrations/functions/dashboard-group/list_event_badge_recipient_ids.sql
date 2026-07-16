-- Returns verified confirmed attendees eligible for an event badge award.
create or replace function list_event_badge_recipient_ids(
    p_group_id uuid,
    p_event_id uuid,
    p_checked_in_only boolean
)
returns uuid[] as $$
    select coalesce(array_agg(ea.user_id order by ea.user_id), '{}'::uuid[])
    from event_attendee ea
    join event e using (event_id)
    join "user" u using (user_id)
    where e.canceled = false
    and e.deleted = false
    and e.event_id = p_event_id
    and e.group_id = p_group_id
    and ea.status = 'confirmed'
    and (not p_checked_in_only or ea.checked_in = true)
    and u.email_verified = true;
$$ language sql;
