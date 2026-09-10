-- Returns the check-in credential of a user's confirmed event attendance.
create or replace function get_user_check_in_code(
    p_event_id uuid,
    p_user_id uuid
) returns uuid as $$
    select ea.check_in_code
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = p_user_id
    and ea.status = 'confirmed';
$$ language sql;
