-- Reports whether a pending external payment hold is due its single
-- reminder: the hold lasts at least 24 hours, expires within the next 24
-- hours and has not been reminded.
create or replace function event_purchase_external_reminder_is_due(
    p_purchase event_purchase
)
returns boolean as $$
    select p_purchase.status = 'pending'
        and p_purchase.charge_model = 'external'
        and p_purchase.external_payment_reminder_sent_at is null
        and p_purchase.hold_expires_at is not null
        and p_purchase.created_at
            <= p_purchase.hold_expires_at - interval '24 hours'
        and p_purchase.hold_expires_at
            <= current_timestamp + interval '24 hours'
        and p_purchase.hold_expires_at > current_timestamp;
$$ language sql stable;
