-- Records an idempotent provider application-fee refund and completes its payment job.
create or replace function record_event_purchase_application_fee_adjustment_succeeded(
    p_adjustment_id uuid,
    p_claim_id uuid,
    p_provider_application_fee_refund_id text
)
returns void as $$
declare
    v_adjustment event_purchase_application_fee_adjustment;
    v_job payment_job;
begin
    -- Validate the provider refund reference
    if nullif(btrim(p_provider_application_fee_refund_id), '') is null then
        raise exception 'provider application-fee refund id is required';
    end if;

    -- Lock and load the claimed application-fee adjustment
    select epafa.*
    into v_adjustment
    from event_purchase_application_fee_adjustment epafa
    where epafa.event_purchase_application_fee_adjustment_id = p_adjustment_id
    for update;

    -- Reject unknown adjustment work
    if not found then
        raise exception 'application-fee adjustment not found';
    end if;

    -- Lock the lifecycle row that owns the claim
    select pj.*
    into v_job
    from payment_job pj
    where pj.payment_job_id = v_adjustment.payment_job_id
    for update;

    -- Accept idempotent replay of the same completed provider refund
    if v_job.status = 'completed' then
        -- Reject replay for a different provider refund
        if v_adjustment.provider_application_fee_refund_id <>
            p_provider_application_fee_refund_id then
            raise exception 'application-fee adjustment has a different provider refund';
        end if;

        return;
    end if;

    -- Validate claim ownership before completing the adjustment
    if v_job.claim_id <> p_claim_id or v_job.status <> 'processing' then
        raise exception 'application-fee adjustment claim is stale';
    end if;

    -- Persist the typed outcome and complete the job
    perform apply_event_purchase_application_fee_adjustment_outcome(
        v_adjustment,
        p_provider_application_fee_refund_id
    );
    perform complete_payment_job(v_job.payment_job_id, p_claim_id);
end;
$$ language plpgsql;
