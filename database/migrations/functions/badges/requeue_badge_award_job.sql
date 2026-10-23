-- Requeues one failed badge award job after operator review.
create or replace function requeue_badge_award_job(
    p_badge_award_job_id uuid
)
returns void as $$
begin
    -- Reset only a terminally failed job for another bounded attempt
    update badge_award_job
    set
        completed_at = null,
        error = null,
        failure_count = 0,
        next_attempt_at = current_timestamp,
        status = 'pending',
        updated_at = current_timestamp
    where badge_award_job_id = p_badge_award_job_id
    and status = 'failed';

    if not found then
        raise exception 'failed badge award job not found';
    end if;
end;
$$ language plpgsql;
