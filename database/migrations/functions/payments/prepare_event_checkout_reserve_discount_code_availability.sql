-- Used by prepare_event_checkout_purchase to reserve one discount redemption
create or replace function prepare_event_checkout_reserve_discount_code_availability(
    p_event_discount_code_id uuid
)
returns void as $$
    update event_discount_code
    -- Reserve one available redemption when the discount has limited inventory
    set
        available = available - 1,
        updated_at = current_timestamp
    where event_discount_code_id = p_event_discount_code_id
    and available_override_active
    and available is not null;
$$ language sql;
