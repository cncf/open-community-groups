-- Claims the next due payment job of a kind for a configured payments provider.
create or replace function claim_payment_job(
    p_kind text,
    p_payment_provider_id text
)
returns jsonb as $$
declare
    v_claim_id uuid := gen_random_uuid();
    v_job payment_job;
begin
    -- Claim due work whose domain row is ready, skipping rows other workers hold
    select pj.*
    into v_job
    from payment_job pj
    where pj.kind = p_kind
    and pj.payment_provider_id = p_payment_provider_id
    and pj.status in ('failed', 'pending')
    and pj.attempt_count < payment_job_max_attempts()
    and pj.next_attempt_at <= current_timestamp
    and payment_job_is_ready(pj)
    order by pj.next_attempt_at, pj.created_at, pj.payment_job_id
    for update skip locked
    limit 1;

    -- Return idle state when no compatible work is due
    if not found then
        return null;
    end if;

    -- Pin the claim so only this worker can release or complete it
    update payment_job
    set
        attempt_count = attempt_count + 1,
        claim_id = v_claim_id,
        claimed_at = current_timestamp,
        status = 'processing',
        updated_at = current_timestamp
    where payment_job_id = v_job.payment_job_id
    returning * into v_job;

    -- Return the lifecycle state with the provider context of the job kind
    return payment_job_to_json(v_job) || payment_job_payload(v_job);
end;
$$ language plpgsql;
