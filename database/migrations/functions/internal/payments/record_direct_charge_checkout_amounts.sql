-- Persists the authoritative amounts of a direct-charge checkout on its
-- purchase: total, tax, subtotal, provider charge and application fee, and
-- the final platform fee computed from the subtotal. Purchases whose
-- provisional fee already matches are marked financially reconciled;
-- otherwise a tax-reconciliation fee adjustment is queued for workers.
create or replace function record_direct_charge_checkout_amounts(
    p_purchase event_purchase,
    p_provider_charge_id text,
    p_provider_application_fee_id text,
    p_provider_total_minor bigint,
    p_tax_amount_minor bigint
)
returns void as $$
declare
    v_final_platform_fee_amount_minor bigint;
    v_subtotal_excluding_tax_minor bigint := p_provider_total_minor - p_tax_amount_minor;
begin
    -- Compute the platform fee owed on the tax-exclusive subtotal, rounding down
    v_final_platform_fee_amount_minor := (v_subtotal_excluding_tax_minor * p_purchase.platform_fee_bps) / 10000;

    -- Persist authoritative amounts and reconcile purchases with unchanged fees
    update event_purchase
    set
        final_platform_fee_amount_minor = v_final_platform_fee_amount_minor,
        financially_reconciled_at = case
            -- Reconcile purchases whose provisional fee already matches
            when provisional_platform_fee_amount_minor = v_final_platform_fee_amount_minor
            then coalesce(financially_reconciled_at, current_timestamp)
            -- Leave fee-adjusted purchases to the adjustment worker
            else financially_reconciled_at
        end,
        provider_application_fee_id = coalesce(p_provider_application_fee_id, p_purchase.provider_application_fee_id),
        provider_charge_id = p_provider_charge_id,
        provider_total_minor = p_provider_total_minor,
        subtotal_excluding_tax_minor = v_subtotal_excluding_tax_minor,
        tax_amount_minor = p_tax_amount_minor,
        updated_at = current_timestamp
    where event_purchase_id = p_purchase.event_purchase_id;

    -- Queue the fee refund owed when tax lowered the final platform fee
    if p_purchase.provisional_platform_fee_amount_minor > v_final_platform_fee_amount_minor then
        insert into event_purchase_application_fee_adjustment (
            amount_minor,
            event_purchase_id,
            idempotency_key,
            kind
        ) values (
            p_purchase.provisional_platform_fee_amount_minor - v_final_platform_fee_amount_minor,
            p_purchase.event_purchase_id,
            format('event-purchase-tax-fee-adjustment-%s', p_purchase.event_purchase_id),
            'tax-reconciliation'
        )
        on conflict (event_purchase_id, kind) do nothing;
    end if;
end;
$$ language plpgsql;
