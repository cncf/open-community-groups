-- Builds the template data shared by the external payment notifications
-- (pending instructions, reminder and expiry) for a purchase hold.
create or replace function external_payment_notification_payload(
    p_event event,
    p_group "group",
    p_purchase event_purchase,
    p_theme jsonb
)
returns jsonb as $$
    select jsonb_strip_nulls(jsonb_build_object(
        'amount_minor', p_purchase.amount_minor,
        'currency_code', p_purchase.currency_code,
        'dashboard_url', '/dashboard/user?tab=events',
        'deadline', epoch_seconds(p_purchase.hold_expires_at),
        'event_id', p_event.event_id,
        'event_name', p_event.name,
        'event_purchase_id', p_purchase.event_purchase_id,
        'external_payment_instructions', p_event.external_payment_instructions,
        'external_payment_url', p_event.external_payment_url,
        'group_name', p_group.name,
        'theme', p_theme,
        'ticket_title', p_purchase.ticket_title,
        'timezone', p_event.timezone
    ));
$$ language sql immutable;
