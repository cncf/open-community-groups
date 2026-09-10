-- Records an in-progress provider refund for the current idempotency attempt.
create or replace function record_event_purchase_refund_pending(
    p_event_purchase_refund_id uuid,
    p_expected_idempotency_key text,
    p_provider_refund_id text,
    p_expected_claim_id uuid default null
)
returns jsonb as $$
declare
    v_job payment_job;
    v_refund event_purchase_refund;
begin
    -- Validate the provider attempt identifiers
    if nullif(btrim(p_expected_idempotency_key), '') is null then
        raise exception 'expected idempotency key is required';
    end if;

    -- Require the provider refund the attempt produced
    if nullif(btrim(p_provider_refund_id), '') is null then
        raise exception 'provider refund id is required';
    end if;

    -- Lock the durable refund row before accepting the provider result
    select epr.*
    into v_refund
    from event_purchase_refund epr
    where epr.event_purchase_refund_id = p_event_purchase_refund_id
    for update;

    -- Reject unknown refunds
    if not found then
        raise exception 'event purchase refund not found';
    end if;

    -- Lock the payment job that owns the worker claim
    select pj.*
    into v_job
    from payment_job pj
    where pj.payment_job_id = v_refund.payment_job_id
    for update;

    -- Reject results from a worker that no longer owns the job
    if v_job.claim_id is distinct from p_expected_claim_id then
        raise exception 'event purchase refund claim is stale';
    end if;

    -- Ignore stale attempts and avoid reviving completed or terminal refunds
    if v_job.idempotency_key = p_expected_idempotency_key then
        -- Reject a result that conflicts with the pinned provider refund
        if v_refund.provider_refund_id is not null
           and v_refund.provider_refund_id <> p_provider_refund_id then
            raise exception 'event purchase refund already has a different provider refund id';
        end if;

        -- Record provider progress without reviving a terminal refund
        if v_refund.status not in ('finalized', 'provider-succeeded')
           and not (
               v_refund.status = 'provider-failed'
               and v_refund.terminal_failure
           ) then
            update event_purchase_refund
            set
                provider_refund_id = p_provider_refund_id,
                status = 'provider-pending',
                updated_at = current_timestamp
            where event_purchase_refund_id = p_event_purchase_refund_id
            returning * into v_refund;

            -- Release the claim and check the provider again after the backoff
            update payment_job
            set
                claim_id = null,
                claimed_at = null,
                failure_message = null,
                next_attempt_at = current_timestamp + payment_job_retry_delay(attempt_count),
                status = 'pending',
                updated_at = current_timestamp
            where payment_job_id = v_job.payment_job_id
            returning * into v_job;
        end if;
    end if;

    -- Return the durable refund state after recording provider progress
    return event_purchase_refund_to_json(v_refund, v_job);
end;
$$ language plpgsql;
