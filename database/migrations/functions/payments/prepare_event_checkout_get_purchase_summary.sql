-- Returns the checkout response summary for a purchase.
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
            'provisional_platform_fee_amount_minor',
                ep.provisional_platform_fee_amount_minor,
            'status', ep.status,
            'ticket_title', ep.ticket_title,

            'completed_at', extract(epoch from ep.completed_at)::bigint,
            'discount_code', ep.discount_code,
            'hold_expires_at', extract(epoch from ep.hold_expires_at)::bigint,
            'manual_tax_rate_ids', ep.manual_tax_rate_ids,
            'provider_checkout_url', ep.provider_checkout_url,
            'provider_object_account_id', ep.provider_object_account_id,
            'provider_payment_reference', ep.provider_payment_reference,
            'provider_session_id', ep.provider_checkout_session_id,
            'provider_total_minor', ep.provider_total_minor,
            'refunded_at', extract(epoch from ep.refunded_at)::bigint,
            'seller', ep.seller_snapshot,
            'tax_behavior', ep.tax_behavior,
            'tax_calculation_mode', ep.tax_calculation_mode,
            'tax_code', ep.provider_tax_code,
            'venue', ep.venue_snapshot
        )
    )
    from event_purchase ep
    where ep.event_purchase_id = p_event_purchase_id;
$$ language sql;
