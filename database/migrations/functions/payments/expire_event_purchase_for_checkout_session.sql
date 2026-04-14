-- Used by the checkout-expired webhook handler: expires the pending purchase
-- linked to the provider checkout session and restores reserved discounts
create or replace function expire_event_purchase_for_checkout_session(
    p_provider text,
    p_provider_session_id text
)
returns void as $$
declare
    v_event_discount_code_id uuid;
begin
    -- Expire the pending purchase linked to the provider checkout session
    update event_purchase
    set
        status = 'expired',
        updated_at = current_timestamp
    where payment_provider_id = p_provider
    and provider_checkout_session_id = p_provider_session_id
    and status = 'pending'
    returning event_discount_code_id into v_event_discount_code_id;

    -- Restore any reserved discount usage released by the expired purchase
    if v_event_discount_code_id is not null then
        perform release_event_discount_code_availability(v_event_discount_code_id);
    end if;
end;
$$ language plpgsql;
