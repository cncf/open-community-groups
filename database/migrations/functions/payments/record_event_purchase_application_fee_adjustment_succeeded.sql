-- Records an idempotent provider application-fee refund.
create or replace function record_event_purchase_application_fee_adjustment_succeeded(
    p_adjustment_id uuid,
    p_claim_id uuid,
    p_provider_application_fee_refund_id text
)
returns void as $$
declare
    v_adjustment event_purchase_application_fee_adjustment;
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

    if not found then
        raise exception 'application-fee adjustment not found';
    end if;

    -- Accept idempotent replay of the same completed provider refund
    if v_adjustment.status = 'completed' then
        if v_adjustment.provider_application_fee_refund_id <>
            p_provider_application_fee_refund_id then
            raise exception 'application-fee adjustment has a different provider refund';
        end if;
        return;
    end if;

    -- Validate claim ownership before completing the adjustment
    if v_adjustment.claim_id <> p_claim_id or v_adjustment.status <> 'processing' then
        raise exception 'application-fee adjustment claim is stale';
    end if;

    -- Persist the successful provider refund
    update event_purchase_application_fee_adjustment
    set
        claim_id = null,
        claimed_at = null,
        completed_at = current_timestamp,
        failure_message = null,
        provider_application_fee_refund_id = p_provider_application_fee_refund_id,
        status = 'completed',
        updated_at = current_timestamp
    where event_purchase_application_fee_adjustment_id = p_adjustment_id;

    -- Tax reconciliation is the only adjustment gating payment reconciliation
    if v_adjustment.kind = 'tax-reconciliation' then
        update event_purchase
        set
            financially_reconciled_at = coalesce(
                financially_reconciled_at,
                current_timestamp
            ),
            updated_at = current_timestamp
        where event_purchase_id = v_adjustment.event_purchase_id;
    end if;
end;
$$ language plpgsql;
