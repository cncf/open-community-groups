-- Validates a provider refund result and locks its event, purchase, refund and
-- payment job in the global order, rejecting results from a stale worker claim.
create or replace function lock_event_purchase_refund_result(
    p_event_purchase_refund_id uuid,
    p_expected_idempotency_key text,
    p_provider_refund_id text,
    p_expected_claim_id uuid
)
returns table (
    job_row payment_job,
    refund_row event_purchase_refund
) as $$
declare
    v_event_id uuid;
    v_job payment_job;
    v_refund event_purchase_refund;
begin
    -- Require the idempotency key of the attempt that produced the result
    if nullif(btrim(p_expected_idempotency_key), '') is null then
        raise exception 'expected idempotency key is required';
    end if;

    -- Require the provider refund the attempt produced
    if nullif(btrim(p_provider_refund_id), '') is null then
        raise exception 'provider refund id is required';
    end if;

    -- Resolve the event that owns the refund
    select ep.event_id
    into v_event_id
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id;

    -- Reject unknown refunds
    if not found then
        raise exception 'event purchase refund not found';
    end if;

    -- Lock the event before its purchase and durable refund
    perform 1
    from event
    where event_id = v_event_id
    for update;

    -- Lock the purchase and durable refund before accepting the provider result
    select epr.*
    into v_refund
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id
    for update of ep, epr;

    -- Reject refunds removed while waiting for the locks
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

    -- Return the locked rows for the caller's outcome decisions
    return query select v_job, v_refund;
end;
$$ language plpgsql;
