-- Releases a payment job claim after a retryable failure and schedules the next attempt.
create or replace function record_payment_job_failure(
    p_payment_job_id uuid,
    p_claim_id uuid,
    p_failure_message text
)
returns void as $$
begin
    -- Release only the current claim with bounded exponential backoff
    update payment_job
    set
        claim_id = null,
        claimed_at = null,
        failure_message = coalesce(
            nullif(btrim(p_failure_message), ''),
            'payment job attempt failed'
        ),
        next_attempt_at = current_timestamp + payment_job_retry_delay(attempt_count),
        status = 'failed',
        updated_at = current_timestamp
    where payment_job_id = p_payment_job_id
    and claim_id = p_claim_id
    and status = 'processing';

    -- Reject releases from a worker that no longer owns the job
    if not found then
        raise exception 'payment job claim is stale';
    end if;
end;
$$ language plpgsql;
