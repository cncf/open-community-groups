-- Expires the pending checkout holds of an event whose deadline passed or
-- whose admission offer lapsed, delegating each expiry to
-- expire_event_checkout_hold and notifying attendees of expired external holds.
-- Callers hold the event enrollment locks.
create or replace function expire_event_checkout_holds(
    p_event event,
    p_group "group",
    p_theme jsonb
)
returns void as $$
declare
    v_purchase event_purchase;
begin
    -- Expire stale checkout holds, including holds that outlive their offer
    for v_purchase in
        select ep.*
        from event_purchase ep
        left join admission_offer ao on ao.admission_offer_id = ep.admission_offer_id
        where ep.event_id = p_event.event_id
        and ep.status = 'pending'
        and (
            ep.hold_expires_at <= current_timestamp
            or admission_offer_is_lapsed(ao.status, ao.expires_at)
        )
        order by ep.event_purchase_id
    loop
        -- Expire the hold, skipping holds expired by a concurrent reconciliation
        if not expire_event_checkout_hold(v_purchase.event_purchase_id) then
            continue;
        end if;

        -- Notify attendees whose external payment window expired, quoting the original deadline
        if v_purchase.charge_model = 'external' then
            perform enqueue_notification(
                'event-external-payment-expired',
                external_payment_notification_payload(p_event, p_group, v_purchase, p_theme),
                '[]'::jsonb,
                array[v_purchase.user_id]
            );
        end if;
    end loop;
end;
$$ language plpgsql;
