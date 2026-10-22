-- Records a terminal provider refund failure for manual recovery.
create or replace function record_event_purchase_refund_terminal_failed(
    p_event_purchase_refund_id uuid,
    p_expected_idempotency_key text,
    p_provider_refund_id text,
    p_failure_message text,
    p_expected_claim_id uuid default null
)
returns void as $$
declare
    v_event_id uuid;
    v_job payment_job;
    v_refund event_purchase_refund;
begin
    -- Validate the provider attempt identifiers
    perform validate_event_purchase_refund_result(p_expected_idempotency_key, p_provider_refund_id);

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

    -- Lock the purchase and durable refund before recording terminal failure
    select epr.*
    into v_refund
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id
    for update of ep, epr;

    -- Lock the payment job that owns the worker claim
    select pj.*
    into v_job
    from payment_job pj
    where pj.payment_job_id = v_refund.payment_job_id
    for update;

    -- Reject refunds removed while waiting for the locks or claimed by another worker
    perform ensure_event_purchase_refund_claim(v_refund, v_job, p_expected_claim_id);

    -- Ignore stale attempts
    if v_job.idempotency_key <> p_expected_idempotency_key then
        return;
    end if;

    -- Reject a result that conflicts with the pinned provider refund
    if v_refund.provider_refund_id is not null
       and v_refund.provider_refund_id <> p_provider_refund_id then
        raise exception 'event purchase refund already has a different provider refund id';
    end if;

    -- Treat the repeated terminal result for a pinned attempt as an idempotent replay
    if v_refund.status = 'provider-failed'
       and v_refund.terminal_failure
       and v_refund.provider_refund_id = p_provider_refund_id then
        return;
    end if;

    -- Pin the terminal provider attempt so it cannot be retried automatically
    update event_purchase_refund
    set
        provider_refund_id = p_provider_refund_id,
        provider_refunded_at = null,
        status = 'provider-failed',
        terminal_failure = true,
        updated_at = current_timestamp
    where event_purchase_refund_id = p_event_purchase_refund_id;

    -- Park the job with the provider diagnostics until an operator recovers it
    update payment_job
    set
        claim_id = null,
        claimed_at = null,
        completed_at = null,
        failure_message = concat_ws(
            ': ',
            nullif(btrim(p_failure_message), ''),
            p_provider_refund_id
        ),
        status = 'failed',
        updated_at = current_timestamp
    where payment_job_id = v_job.payment_job_id;

    -- Expose post-finalization failures and block another checkout during recovery
    if v_refund.finalized_at is not null then
        update event_purchase
        set
            status = 'refund-recovery-pending',
            updated_at = current_timestamp
        where event_purchase_id = v_refund.event_purchase_id
        and status in ('refunded', 'refund-recovery-pending');

        -- Reject finalized refunds whose purchase left the refunded states
        if not found then
            raise exception 'finalized event purchase not found';
        end if;
    end if;
end;
$$ language plpgsql;
