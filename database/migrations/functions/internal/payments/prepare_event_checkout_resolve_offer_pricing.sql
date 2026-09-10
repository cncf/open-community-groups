-- Resolves checkout pricing from the immutable snapshot stored on a claimed
-- admission offer. A submitted discount code must match the snapshotted one;
-- otherwise the offer price is reported as locked and no pricing is returned.
-- An omitted code reuses the snapshotted code.
create or replace function prepare_event_checkout_resolve_offer_pricing(
    p_admission_offer admission_offer,
    p_discount_code text
)
returns table (
    currency_code text,
    discount_amount_minor bigint,
    discount_code text,
    event_discount_code_id uuid,
    final_amount_minor bigint,
    price_locked boolean,
    ticket_title text
) as $$
declare
    v_snapshot_discount_code text := upper(nullif(btrim(p_admission_offer.discount_code), ''));
begin
    -- Report attempts to replace the snapshotted discount code
    if p_discount_code is not null and v_snapshot_discount_code is distinct from p_discount_code then
        return query select null::text, null::bigint, null::text, null::uuid, null::bigint, true, null::text;
        return;
    end if;

    -- Return the frozen pricing with the snapshotted code
    return query select
        p_admission_offer.currency_code,
        p_admission_offer.discount_amount_minor,
        v_snapshot_discount_code,
        p_admission_offer.event_discount_code_id,
        p_admission_offer.amount_minor,
        false,
        p_admission_offer.ticket_title;
end;
$$ language plpgsql;
