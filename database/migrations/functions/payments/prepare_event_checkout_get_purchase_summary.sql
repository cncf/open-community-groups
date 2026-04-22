-- Used by prepare_event_checkout_purchase to build the checkout response payload
create or replace function prepare_event_checkout_get_purchase_summary(
    p_event_purchase_id uuid
)
returns jsonb as $$
    select jsonb_strip_nulls(
        jsonb_build_object(
            'amount_minor', ep.amount_minor,
            'currency_code', ep.currency_code,
            'discount_amount_minor', ep.discount_amount_minor,
            'event_purchase_id', ep.event_purchase_id,
            'event_ticket_type_id', ep.event_ticket_type_id,
            'status', ep.status,
            'ticket_title', ep.ticket_title,

            'completed_at', extract(epoch from ep.completed_at)::bigint,
            'discount_code', ep.discount_code,
            'hold_expires_at', extract(epoch from ep.hold_expires_at)::bigint,
            'provider_checkout_url', ep.provider_checkout_url,
            'provider_payment_reference', ep.provider_payment_reference,
            'provider_session_id', ep.provider_checkout_session_id,
            'refunded_at', extract(epoch from ep.refunded_at)::bigint
        )
    )
    from event_purchase ep
    where ep.event_purchase_id = p_event_purchase_id;
$$ language sql;
