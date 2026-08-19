-- Requeues application-fee adjustment claims left processing by interrupted workers.
create or replace function requeue_stale_event_purchase_application_fee_adjustment_claims()
returns int as $$
declare
    v_count int;
begin
    -- Release claims only after the worker processing timeout
    update event_purchase_application_fee_adjustment
    set
        claim_id = null,
        claimed_at = null,
        failure_message = case
            -- Record final expiration when no provider error exists
            when attempt_count >= 10 and failure_message is null then
                'Application-fee adjustment worker claim expired after the final automatic attempt; provider outcome is unknown'
            -- Retain the provider error and add one final-attempt expiration notice
            when attempt_count >= 10 then concat(
                failure_message,
                E'\nApplication-fee adjustment worker claim expired after the final automatic attempt; provider outcome is unknown'
            )
            -- Preserve or initialize retryable failure context below the limit
            else coalesce(
                failure_message,
                'Application-fee adjustment worker claim expired'
            )
        end,
        next_attempt_at = case
            -- Make retryable work immediately available
            when attempt_count < 10 then current_timestamp
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
