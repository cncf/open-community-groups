-- Validates an event for checkout and returns its configured currency.
create or replace function prepare_event_checkout_validate_event(
    p_community_id uuid,
    p_event_id uuid
)
returns text as $$
declare
    v_event event;
begin
    -- Lock and validate the event before checkout starts
    v_event := lock_active_event(p_community_id, null, p_event_id, true);

    -- Return the optional event currency after state validation
    return v_event.payment_currency_code;
end;
$$ language plpgsql;
