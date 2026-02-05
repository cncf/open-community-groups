-- Updates a CFS submission for an event.
create or replace function update_cfs_submission(
    p_reviewer_id uuid,
    p_event_id uuid,
    p_cfs_submission_id uuid,
    p_submission jsonb
)
returns void as $$
begin
    -- Validate submission status provided
    if p_submission->>'status_id' is null
        or p_submission->>'status_id' not in (
            'approved',
            'information-requested',
            'not-reviewed',
            'rejected'
        ) then
        raise exception 'invalid submission status';
    end if;

    -- Update submission
    update cfs_submission set
        action_required_message = nullif(p_submission->>'action_required_message', ''),
        reviewed_by = p_reviewer_id,
        status_id = p_submission->>'status_id',
        updated_at = current_timestamp
    where cfs_submission_id = p_cfs_submission_id
    and event_id = p_event_id
    and status_id <> 'withdrawn';

    if not found then
        raise exception 'submission not found';
    end if;
end;
$$ language plpgsql;
