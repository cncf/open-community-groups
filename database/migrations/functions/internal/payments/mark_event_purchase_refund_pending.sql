-- Moves a locked purchase that can no longer be fulfilled into the
-- refund-pending state, recording the provider payment reference the refund
-- needs, releasing the discount reservation of a pending hold and the
-- checkout attendee row.
create or replace function mark_event_purchase_refund_pending(
    p_purchase event_purchase,
    p_provider_payment_reference text
)
returns void as $$
begin
    -- Persist the refund-pending state before the provider refund step
    update event_purchase
    set
        hold_expires_at = null,
        provider_payment_reference = p_provider_payment_reference,
        status = 'refund-pending',
        updated_at = current_timestamp
    where event_purchase_id = p_purchase.event_purchase_id;

    -- Release the discount reservation only when expiring a pending hold
    if p_purchase.status = 'pending' and p_purchase.event_discount_code_id is not null then
        perform release_event_discount_code_availability(p_purchase.event_discount_code_id);
    end if;

    -- Release the pending attendee row created for checkout answers
    perform release_event_checkout_attendee_hold(p_purchase.event_id, p_purchase.user_id);
end;
$$ language plpgsql;
