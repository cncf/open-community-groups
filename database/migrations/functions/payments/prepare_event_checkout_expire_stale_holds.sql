-- Used by prepare_event_checkout_purchase to expire timed-out holds before checkout
create or replace function prepare_event_checkout_expire_stale_holds(
    p_event_id uuid
)
returns void as $$
declare
    v_expired_purchase record;
begin
    -- Expire stale pending purchases and restore any released discount capacity
    for v_expired_purchase in
        with expired_purchase as (
            update event_purchase
            set
                status = 'expired',
                updated_at = current_timestamp
            where event_id = p_event_id
            and status = 'pending'
            and hold_expires_at <= current_timestamp
            returning event_discount_code_id
        )
        select
            event_discount_code_id,
            count(*)::int as purchase_count
        from expired_purchase
        where event_discount_code_id is not null
        group by event_discount_code_id
    loop
        perform release_event_discount_code_availability(
            v_expired_purchase.event_discount_code_id,
            v_expired_purchase.purchase_count
        );
    end loop;
end;
$$ language plpgsql;
