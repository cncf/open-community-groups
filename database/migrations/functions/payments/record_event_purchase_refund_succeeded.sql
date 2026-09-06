-- Records a successful provider refund for the expected attempt.
create or replace function record_event_purchase_refund_succeeded(
    p_event_purchase_refund_id uuid,
    p_expected_idempotency_key text,
    p_provider_refund_id text,
    p_expected_claim_id uuid default null
)
returns jsonb as $$
declare
    v_event_id uuid;
    v_job payment_job;
    v_payment_job_id uuid;
    v_purchase event_purchase;
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

    -- Resolve and lock the event before its purchase and durable refund
    select ep.event_id
    into v_event_id
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id;

    -- Reject unknown refunds
    if not found then
        raise exception 'event purchase refund not found';
    end if;

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

    -- Ignore superseded attempts and delayed success for terminal refunds
    if v_job.idempotency_key = p_expected_idempotency_key
       and not (
           v_refund.status = 'provider-failed'
           and v_refund.terminal_failure
       ) then
        -- Reject a result that conflicts with the pinned provider refund
        if v_refund.provider_refund_id is not null
           and v_refund.provider_refund_id <> p_provider_refund_id then
            raise exception 'event purchase refund already has a different provider refund id';
        end if;

        -- Record provider success without downgrading local finalization
        if v_refund.status <> 'finalized' then
            update event_purchase_refund
            set
                provider_refund_id = p_provider_refund_id,
                provider_refunded_at = coalesce(provider_refunded_at, current_timestamp),
                status = case
                    -- Local finalization still has to run
                    when finalized_at is null then 'provider-succeeded'
                    -- The provider confirmed a refund that was already finalized locally
                    else 'finalized'
                end,
                terminal_failure = false,
                updated_at = current_timestamp
            where event_purchase_refund_id = p_event_purchase_refund_id
            returning * into v_refund;
        end if;

        -- Restore the accurate purchase state and close the job when finalization already ran
        if v_refund.finalized_at is not null then
            update event_purchase
            set
                refunded_at = coalesce(refunded_at, current_timestamp),
                status = 'refunded',
                updated_at = current_timestamp
            where event_purchase_id = v_refund.event_purchase_id
            and status = 'refund-recovery-pending';

            -- Require the purchase to already be refunded when no recovery was pending
            if not found then
                perform 1
                from event_purchase
                where event_purchase_id = v_refund.event_purchase_id
                and status = 'refunded';

                -- Reject finalized refunds whose purchase left the refunded states
                if not found then
                    raise exception 'finalized event purchase not found';
                end if;
            end if;

            perform complete_payment_job(v_job.payment_job_id, p_expected_claim_id);

        -- Give local finalization a fresh attempt budget now that the provider confirmed
        else
            update payment_job
            set
                attempt_count = 0,
                failure_message = null,
                next_attempt_at = current_timestamp,
                status = case
                    -- Keep the claim of the worker that reported the success
                    when status = 'processing' then status
                    -- Make unclaimed work due immediately
                    else 'pending'
                end,
                updated_at = current_timestamp
            where payment_job_id = v_job.payment_job_id;
        end if;

        -- Queue direct-charge fee and document work without another customer refund
        select ep.*
        into v_purchase
        from event_purchase ep
        where ep.event_purchase_id = v_refund.event_purchase_id;

        -- Return the platform fee collected on the refunded charge
        if v_purchase.final_platform_fee_amount_minor > 0 then
            v_payment_job_id := enqueue_payment_job(
                'event-purchase-application-fee-adjustment',
                v_purchase.payment_provider_id,
                v_purchase.event_purchase_id,
                format('event-purchase-refund-fee-adjustment-%s', v_purchase.event_purchase_id)
            );

            -- Create the adjustment only once per purchase refund
            if v_payment_job_id is not null then
                insert into event_purchase_application_fee_adjustment (
                    amount_minor,
                    event_purchase_id,
                    kind,
                    payment_job_id
                ) values (
                    v_purchase.final_platform_fee_amount_minor,
                    v_purchase.event_purchase_id,
                    'purchase-refund',
                    v_payment_job_id
                );
            end if;
        end if;

        -- Document invoiced purchases with a linked credit note
        if v_purchase.provider_invoice_id is not null then
            v_payment_job_id := enqueue_payment_job(
                'event-purchase-credit-note',
                v_purchase.payment_provider_id,
                v_purchase.event_purchase_id,
                format('event-purchase-credit-note-%s', v_refund.event_purchase_refund_id)
            );

            -- Create the credit note only once per refund
            if v_payment_job_id is not null then
                insert into event_purchase_credit_note (
                    amount_minor,
                    currency_code,
                    event_purchase_refund_id,
                    payment_job_id,
                    payment_provider_id,
                    provider_object_account_id,
                    tax_amount_minor
                ) values (
                    v_purchase.provider_total_minor,
                    v_purchase.currency_code,
                    v_refund.event_purchase_refund_id,
                    v_payment_job_id,
                    v_purchase.payment_provider_id,
                    v_purchase.provider_object_account_id,
                    v_purchase.tax_amount_minor
                );
            end if;
        end if;
    end if;

    -- Return the durable refund state after recording provider success
    select pj.*
    into v_job
    from payment_job pj
    where pj.payment_job_id = v_refund.payment_job_id;

    return event_purchase_refund_to_json(v_refund, v_job);
end;
$$ language plpgsql;
