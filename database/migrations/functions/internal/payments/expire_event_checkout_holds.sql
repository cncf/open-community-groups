-- Expires the pending checkout holds of an event whose deadline passed or
-- whose admission offer lapsed, releasing their discount reservation and
-- checkout attendee row and notifying attendees of expired external holds.
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
            or (
                admission_offer_is_active(ao.status)
                and ao.expires_at is not null
                and ao.expires_at <= current_timestamp
            )
        )
        order by ep.event_purchase_id
    loop
        update event_purchase
        set
            hold_expires_at = least(hold_expires_at, current_timestamp),
            status = 'expired',
            updated_at = current_timestamp
        where event_purchase_id = v_purchase.event_purchase_id
        and status = 'pending';

        -- Skip holds expired by a concurrent reconciliation
        if not found then
            continue;
        end if;

        -- Restore the reserved discount inventory
        if v_purchase.event_discount_code_id is not null then
            perform release_event_discount_code_availability(v_purchase.event_discount_code_id);
        end if;

        -- Release the pending attendee row created for checkout answers
        perform release_event_checkout_attendee_hold(p_event.event_id, v_purchase.user_id);

        -- Notify attendees whose external payment window expired
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
