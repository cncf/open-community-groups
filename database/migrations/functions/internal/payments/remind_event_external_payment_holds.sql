-- Sends one reminder for each pending external payment hold of an event that
-- expires within the next 24 hours, marking the purchase before enqueueing so
-- retries cannot duplicate it. Callers hold the event enrollment locks.
create or replace function remind_event_external_payment_holds(
    p_event event,
    p_group "group",
    p_theme jsonb
)
returns void as $$
declare
    v_purchase event_purchase;
begin
    -- Remind holders whose deadline is within the reminder window
    for v_purchase in
        select ep.*
        from event_purchase ep
        where ep.event_id = p_event.event_id
        and ep.status = 'pending'
        and ep.charge_model = 'external'
        and ep.external_payment_reminder_sent_at is null
        and ep.hold_expires_at is not null
        and ep.created_at <= ep.hold_expires_at - interval '24 hours'
        and ep.hold_expires_at - interval '24 hours' <= current_timestamp
        and ep.hold_expires_at > current_timestamp
        order by ep.event_purchase_id
    loop
        -- Mark the reminder before enqueueing so retries cannot duplicate it
        update event_purchase
        set
            external_payment_reminder_sent_at = current_timestamp,
            updated_at = current_timestamp
        where event_purchase_id = v_purchase.event_purchase_id
        and external_payment_reminder_sent_at is null
        and status = 'pending';

        -- Skip purchases claimed by a concurrent reminder
        if not found then
            continue;
        end if;

        perform enqueue_notification(
            'event-external-payment-reminder',
            external_payment_notification_payload(p_event, p_group, v_purchase, p_theme),
            '[]'::jsonb,
            array[v_purchase.user_id]
        );
    end loop;
end;
$$ language plpgsql;
