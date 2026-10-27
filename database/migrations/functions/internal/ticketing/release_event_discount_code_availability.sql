-- Returns one reserved redemption to an event discount code.
create or replace function release_event_discount_code_availability(
    p_event_discount_code_id uuid
)
returns void as $$
    update event_discount_code
    -- Return one redemption when the discount has limited inventory
    set
        available = available + 1,
        updated_at = current_timestamp
    where event_discount_code_id = p_event_discount_code_id
    and available_override_active
    and available is not null;
$$ language sql volatile;
