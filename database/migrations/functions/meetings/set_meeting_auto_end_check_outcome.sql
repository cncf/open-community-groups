-- set_meeting_auto_end_check_outcome records the auto-end check outcome for a meeting.
create or replace function set_meeting_auto_end_check_outcome(
    p_meeting_id uuid,
    p_outcome text
) returns void as $$
    update meeting
    set auto_end_check_at = current_timestamp,
        auto_end_check_outcome = p_outcome,
        updated_at = current_timestamp
    where meeting_id = p_meeting_id;
$$ language sql;
