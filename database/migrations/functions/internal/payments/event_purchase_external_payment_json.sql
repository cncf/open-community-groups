-- Projects a pending external payment into the JSON read by Rust enrollment and dashboard DTOs.
create or replace function event_purchase_external_payment_json(
    p_event event,
    p_purchase event_purchase
)
returns jsonb as $$
    select jsonb_strip_nulls(jsonb_build_object(
        'amount_minor', p_purchase.amount_minor,
        'currency_code', p_purchase.currency_code,
        'deadline', epoch_seconds(p_purchase.hold_expires_at),
        'instructions', p_event.external_payment_instructions,
        'reference', p_purchase.event_purchase_id,
        'url', p_event.external_payment_url
    ));
$$ language sql stable;
