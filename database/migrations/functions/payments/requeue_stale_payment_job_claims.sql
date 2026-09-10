-- Releases payment job claims left processing by interrupted workers.
create or replace function requeue_stale_payment_job_claims()
returns int as $$
declare
    v_count int;
begin
    -- Release claims only after the worker processing timeout
    update payment_job
    set
        claim_id = null,
        claimed_at = null,
        failure_message = case
            -- Surface an abandoned final attempt without losing provider diagnostics
            when attempt_count >= payment_job_max_attempts() then concat_ws(
                E'\n',
                failure_message,
                'payment job claim expired after the final automatic attempt; provider outcome is unknown'
            )
            -- Preserve or initialize retryable failure context below the limit
            else coalesce(failure_message, 'payment job claim expired')
        end,
        next_attempt_at = case
            -- Make retryable work immediately available
            when attempt_count < payment_job_max_attempts() then current_timestamp
            -- Preserve scheduling metadata for operator-visible final failures
            else next_attempt_at
        end,
        status = 'failed',
        updated_at = current_timestamp
    where status = 'processing'
    and claimed_at < current_timestamp - interval '15 minutes';

    -- Return the number of claims released by this sweep
    get diagnostics v_count = row_count;
    return v_count;
end;
$$ language plpgsql;
