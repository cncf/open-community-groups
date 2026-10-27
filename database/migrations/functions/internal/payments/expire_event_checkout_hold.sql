-- Expires a pending checkout hold without moving a lapsed deadline forward,
-- restores its discount reservation and releases the checkout attendee row.
-- Returns whether the purchase was still pending. Callers hold the event
-- enrollment locks.
create or replace function expire_event_checkout_hold(
    p_event_purchase_id uuid
)
returns boolean as $$
declare
    v_purchase event_purchase;
begin
    -- Expire the hold while it is still pending
    update event_purchase
    set
        hold_expires_at = least(hold_expires_at, current_timestamp),
        status = 'expired',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id
    and status = 'pending'
    returning * into v_purchase;

    -- Skip purchases that are no longer pending
    if not found then
        return false;
    end if;

    -- Restore the discount inventory reserved by the hold
    if v_purchase.event_discount_code_id is not null then
        perform release_event_discount_code_availability(v_purchase.event_discount_code_id);
    end if;

    -- Release the pending attendee row created for checkout answers
    perform release_event_checkout_attendee_hold(v_purchase.event_id, v_purchase.user_id);

    -- Report that the hold was expired
    return true;
end;
$$ language plpgsql;
