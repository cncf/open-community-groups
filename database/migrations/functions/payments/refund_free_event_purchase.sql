-- Refund a free event purchase and restore any reserved discount usage.
create or replace function refund_free_event_purchase(
    p_event_purchase_id uuid
)
returns void as $$
declare
    v_event_discount_code_id uuid;
begin
    -- Lock the purchase and validate that a free completed purchase exists
    select event_discount_code_id
    into v_event_discount_code_id
    from event_purchase
    where event_purchase_id = p_event_purchase_id
    and amount_minor = 0
    and status in ('completed', 'refund-requested')
    for update;

    if not found then
        raise exception 'free purchase not found';
    end if;

    -- Persist the refunded purchase state for the free checkout
    update event_purchase
    set
        refunded_at = current_timestamp,
        status = 'refunded',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id;

    -- Release any reserved discount redemption after refunding the purchase
    if v_event_discount_code_id is not null then
        perform release_event_discount_code_availability(v_event_discount_code_id);
    end if;
end;
$$ language plpgsql;
