-- Expires a replaced checkout hold and releases its discount reservation.
create or replace function prepare_event_checkout_expire_previous_hold(
    p_event_purchase_id uuid
)
returns void as $$
declare
    v_event_id uuid;
    v_event_discount_code_id uuid;
    v_user_id uuid;
begin
    -- Expire the replaced pending purchase before creating the new hold
    update event_purchase
    set
        hold_expires_at = current_timestamp,
        status = 'expired',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id
    and status = 'pending'
    returning
        event_discount_code_id,
        event_id,
        user_id
    into
        v_event_discount_code_id,
        v_event_id,
        v_user_id;

    -- Restore any reserved discount inventory tied to the replaced purchase
    if v_event_discount_code_id is not null then
        perform release_event_discount_code_availability(v_event_discount_code_id);
    end if;

    -- Release the pending attendee row created for checkout answers
    if v_event_id is not null then
        perform release_event_checkout_attendee_hold(v_event_id, v_user_id);
    end if;
end;
$$ language plpgsql;
