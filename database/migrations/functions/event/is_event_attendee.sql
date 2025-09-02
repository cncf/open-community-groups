-- Check if a user is an attendee of an event.
create or replace function is_event_attendee(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
) returns boolean as $$
    select exists (
        select 1
        from event_attendee ea
        join event e using (event_id)
        join "group" g on g.group_id = e.group_id
        where ea.event_id = p_event_id
        and ea.user_id = p_user_id
        and g.community_id = p_community_id
    );
$$ language sql;
