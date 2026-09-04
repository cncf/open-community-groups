-- Loads the durable provider refund record for an event purchase.
create or replace function get_event_purchase_refund(
    p_event_purchase_id uuid
)
returns jsonb as $$
declare
    v_refund event_purchase_refund;
begin
    -- Load the durable refund for the requested purchase
    select *
    into v_refund
    from event_purchase_refund
    where event_purchase_id = p_event_purchase_id;

    if not found then
        raise exception 'event purchase refund not found';
    end if;

    -- Return the durable provider and local finalization state
    return event_purchase_refund_to_json(v_refund);
end;
$$ language plpgsql;
