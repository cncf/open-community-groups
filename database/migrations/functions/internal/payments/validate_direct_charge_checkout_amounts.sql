-- Validates the authoritative amounts reported by the provider for a
-- direct-charge checkout against the purchase snapshot: amounts must be
-- present and non-negative with a positive total, no-tax purchases must carry
-- zero tax, the total or subtotal must match the ticket price according to
-- the snapshotted tax behavior, and a reported application fee must match the
-- one already recorded.
create or replace function validate_direct_charge_checkout_amounts(
    p_purchase event_purchase,
    p_provider_total_minor bigint,
    p_tax_amount_minor bigint,
    p_provider_application_fee_id text
)
returns void as $$
declare
    v_subtotal_excluding_tax_minor bigint := p_provider_total_minor - p_tax_amount_minor;
begin
    -- Reject checkouts without complete, coherent authoritative amounts
    if p_provider_total_minor is null
       or p_tax_amount_minor is null
       or p_provider_total_minor <= 0
       or p_tax_amount_minor < 0
       or v_subtotal_excluding_tax_minor < 0 then
        raise exception 'direct-charge checkout is missing authoritative amounts';
    end if;

    -- Enforce the zero-tax contract for events that do not collect tax
    if p_tax_amount_minor <> 0 and p_purchase.tax_calculation_mode = 'none' then
        raise exception 'no-tax checkout must have zero tax';
    end if;

    -- Validate authoritative amounts against the snapshotted display behavior
    if (p_purchase.tax_behavior = 'inclusive' and p_provider_total_minor <> p_purchase.amount_minor)
       or (p_purchase.tax_behavior = 'exclusive' and v_subtotal_excluding_tax_minor <> p_purchase.amount_minor) then
        raise exception 'provider total does not match the ticket tax behavior';
    end if;

    -- Reject an application fee that differs from the recorded one
    if p_purchase.provider_application_fee_id is not null
       and p_provider_application_fee_id is not null
       and p_purchase.provider_application_fee_id <> p_provider_application_fee_id then
        raise exception 'provider application fee does not match the purchase';
    end if;
end;
$$ language plpgsql;
