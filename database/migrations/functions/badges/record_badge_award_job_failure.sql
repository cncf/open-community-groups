-- Releases or terminally fails a badge award job after a processing error.
create or replace function record_badge_award_job_failure(
    p_badge_award_job_id uuid,
    p_claim_id uuid,
    p_error text,
    p_max_failures integer default 10
)
returns boolean as $$
declare
    v_failure_count integer;
    v_is_terminal boolean;
begin
    -- Validate retry controls before changing claim ownership
    if p_max_failures <= 0 then
        raise exception 'badge award job failure limit must be positive';
    end if;

    -- Lock and validate the expected processing claim
    select failure_count + 1
    into v_failure_count
    from badge_award_job
    where badge_award_job_id = p_badge_award_job_id
    and claim_id = p_claim_id
    and status = 'processing'
    for update;

    if not found then
        raise exception 'badge award job claim not found';
    end if;

    v_is_terminal := v_failure_count >= p_max_failures;

    -- Persist either bounded retry scheduling or terminal failure
    update badge_award_job
    set
        claim_id = null,
        claimed_at = null,
        completed_at = case when v_is_terminal then current_timestamp else null end,
        error = left(coalesce(nullif(btrim(p_error), ''), 'badge award processing failed'), 1000),
        failure_count = v_failure_count,
        next_attempt_at = case
            when v_is_terminal then next_attempt_at
            else current_timestamp + make_interval(
                secs => least(1800, 60 * power(2, v_failure_count - 1)::integer)
            )
        end,
        status = case when v_is_terminal then 'failed' else 'pending' end,
        updated_at = current_timestamp
    where badge_award_job_id = p_badge_award_job_id;

    return v_is_terminal;
end;
$$ language plpgsql;
