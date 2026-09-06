-- Completes a payment job after its domain row recorded the provider outcome.
create or replace function complete_payment_job(
    p_payment_job_id uuid,
    p_claim_id uuid
)
returns void as $$
begin
    -- Complete only work that is unclaimed or owned by the given claim
    update payment_job
    set
        claim_id = null,
        claimed_at = null,
        completed_at = current_timestamp,
        failure_message = null,
        status = 'completed',
        updated_at = current_timestamp
    where payment_job_id = p_payment_job_id
    and status <> 'completed'
    and claim_id is not distinct from p_claim_id;

    -- Accept a repeated completion and reject every other miss
    if not found then
        -- Treat an already completed job as an idempotent replay
        perform 1
        from payment_job
        where payment_job_id = p_payment_job_id
        and status = 'completed';

        -- Reject unknown jobs and claims held by another worker
        if not found then
            raise exception 'payment job claim is stale';
        end if;
    end if;
end;
$$ language plpgsql;
