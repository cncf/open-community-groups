-- Used by prepare_event_checkout_purchase to expire a replaced hold and release discounts
create or replace function prepare_event_checkout_expire_previous_hold(
    p_event_purchase_id uuid
)
returns void as $$
declare
    v_event_discount_code_id uuid;
begin
    -- Expire the replaced pending purchase before creating the new hold
    update event_purchase
    set
        hold_expires_at = current_timestamp,
        status = 'expired',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id
    and status = 'pending'
    returning event_discount_code_id into v_event_discount_code_id;

    -- Restore any reserved discount inventory tied to the replaced purchase
    if v_event_discount_code_id is not null then
        perform release_event_discount_code_availability(v_event_discount_code_id);
    end if;
end;
$$ language plpgsql;
