-- Shared helper used by checkout expiration and refund flows to return
-- reserved discount availability to the event discount code pool
create or replace function release_event_discount_code_availability(
    p_event_discount_code_id uuid,
    p_quantity int default 1
)
returns void as $$
    update event_discount_code
    set
        available = available + p_quantity,
        updated_at = current_timestamp
    where event_discount_code_id = p_event_discount_code_id
    and available is not null;
$$ language sql;
