-- Used by start_checkout after creating a provider checkout session: stores
-- the provider, session id, and redirect URL on the pending purchase so later
-- webhooks can reconcile it
create or replace function attach_checkout_session_to_event_purchase(
    p_event_purchase_id uuid,
    p_provider text,
    p_provider_checkout_session_id text,
    p_provider_checkout_url text
)
returns void as $$
    -- Store provider checkout metadata only for a pending purchase that does not
    -- already point at another checkout session
    update event_purchase
    set
        payment_provider_id = p_provider,
        provider_checkout_session_id = p_provider_checkout_session_id,
        provider_checkout_url = p_provider_checkout_url,
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id
    and provider_checkout_session_id is null
    and status = 'pending';
$$ language sql;
