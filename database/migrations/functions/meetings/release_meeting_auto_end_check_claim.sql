-- release_meeting_auto_end_check_claim releases a retryable auto-end claim.
create or replace function release_meeting_auto_end_check_claim(
    p_meeting_id uuid
) returns void as $$
    update meeting
    set
        auto_end_check_claimed_at = null,
        updated_at = current_timestamp
    where meeting_id = p_meeting_id
      and auto_end_check_at is null;
$$ language sql;
