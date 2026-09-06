-- Records the provider application-fee refund of an adjustment and the reconciliation it gates.
create or replace function apply_event_purchase_application_fee_adjustment_outcome(
    p_adjustment event_purchase_application_fee_adjustment,
    p_provider_application_fee_refund_id text
)
returns void as $$
begin
    -- Persist the provider refund on the adjustment
    update event_purchase_application_fee_adjustment
    set
        provider_application_fee_refund_id = p_provider_application_fee_refund_id,
        updated_at = current_timestamp
    where event_purchase_application_fee_adjustment_id =
        p_adjustment.event_purchase_application_fee_adjustment_id;

    -- Tax reconciliation is the only adjustment gating financial reconciliation
    if p_adjustment.kind = 'tax-reconciliation' then
        update event_purchase
        set
            financially_reconciled_at = coalesce(
                financially_reconciled_at,
                current_timestamp
            ),
            updated_at = current_timestamp
        where event_purchase_id = p_adjustment.event_purchase_id;
    end if;
end;
$$ language plpgsql;
