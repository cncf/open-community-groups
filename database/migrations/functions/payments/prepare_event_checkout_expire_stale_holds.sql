-- Expires stale checkout holds for an event.
create or replace function prepare_event_checkout_expire_stale_holds(
    p_event_id uuid
)
returns void as $$
declare
    v_expired_purchase record;
begin
    -- Expire stale pending purchases, release attendee holds, and restore discount capacity
    for v_expired_purchase in
        with expired_purchase as (
            update event_purchase
            set
                status = 'expired',
                updated_at = current_timestamp
            where event_id = p_event_id
            and status = 'pending'
            and hold_expires_at <= current_timestamp
            returning
                event_discount_code_id,
                event_id,
                user_id
        )
        select
            event_discount_code_id,
            event_id,
            user_id
        from expired_purchase
    loop
        -- Restore reserved discount inventory for this expired hold
        if v_expired_purchase.event_discount_code_id is not null then
            perform release_event_discount_code_availability(v_expired_purchase.event_discount_code_id);
        end if;

        -- Release the pending attendee row created for checkout answers
        perform release_event_checkout_attendee_hold(
            v_expired_purchase.event_id,
            v_expired_purchase.user_id
        );
    end loop;
end;
$$ language plpgsql;
