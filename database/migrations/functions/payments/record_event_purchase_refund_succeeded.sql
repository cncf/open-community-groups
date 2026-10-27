-- Records a successful provider refund for the expected attempt.
create or replace function record_event_purchase_refund_succeeded(
    p_event_purchase_refund_id uuid,
    p_expected_idempotency_key text,
    p_provider_refund_id text,
    p_expected_claim_id uuid default null
)
returns jsonb as $$
declare
    v_job payment_job;
    v_lock record;
    v_purchase event_purchase;
    v_refund event_purchase_refund;
begin
    -- Validate the result and lock its rows for the current worker claim
    select *
    into v_lock
    from lock_event_purchase_refund_result(
        p_event_purchase_refund_id,
        p_expected_idempotency_key,
        p_provider_refund_id,
        p_expected_claim_id
    );
    v_job := v_lock.job_row;
    v_refund := v_lock.refund_row;

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

            -- Close the job now that the refund is fully recorded
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
            perform enqueue_event_purchase_application_fee_adjustment(
                v_purchase,
                'purchase-refund',
                v_purchase.final_platform_fee_amount_minor
            );
        end if;

        -- Document invoiced purchases with a linked credit note
        if v_purchase.provider_invoice_id is not null then
            perform enqueue_event_purchase_credit_note(
                v_purchase,
                v_refund.event_purchase_refund_id
            );
        end if;
    end if;

    -- Reload the job state written while recording provider success
    select pj.*
    into v_job
    from payment_job pj
    where pj.payment_job_id = v_refund.payment_job_id;

    -- Return the durable refund state
    return event_purchase_refund_to_json(v_refund, v_job);
end;
$$ language plpgsql;
