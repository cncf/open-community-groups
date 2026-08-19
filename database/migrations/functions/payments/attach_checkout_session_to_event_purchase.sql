-- Attaches an account-scoped provider checkout session to a pending purchase.
create or replace function attach_checkout_session_to_event_purchase(
    p_event_purchase_id uuid,
    p_provider text,
    p_provider_object_account_id text,
    p_provider_checkout_session_id text,
    p_provider_checkout_url text,
    p_provider_tax_location_id text default null,
    p_performance_location_fingerprint text default null,
    p_provider_tax_product_id text default null,
    p_provider_product_fingerprint text default null
)
returns void as $$
declare
    v_purchase event_purchase%rowtype;
begin
    -- Lock and validate the immutable seller scope before attaching provider objects
    select ep.*
    into v_purchase
    from event_purchase ep
    where ep.event_purchase_id = p_event_purchase_id
    for update;

    if not found then
        raise exception 'event purchase not found';
    end if;

    if v_purchase.status <> 'pending' then
        return;
    end if;

    -- Validate the immutable seller and provider scope
    if v_purchase.charge_model <> 'direct-charge'
       or v_purchase.payment_provider_id is distinct from p_provider
       or v_purchase.provider_object_account_id <> p_provider_object_account_id then
        raise exception 'provider account does not match the purchase seller';
    end if;

    -- Require complete provider resources for automatic tax calculation
    if v_purchase.tax_calculation_mode = 'automatic'
       and (
            p_provider_tax_location_id is null
            or p_performance_location_fingerprint is null
            or p_provider_tax_product_id is null
            or p_provider_product_fingerprint is null
       ) then
        raise exception 'automatic ticket tax resources are required';
    end if;

    -- A concurrent checkout request may already have attached the canonical
    -- session; preserve it so the caller can reload and reuse it
    if v_purchase.provider_checkout_session_id is not null then
        return;
    end if;

    -- Preserve the provider tax location for account-scoped reuse
    if p_provider_tax_location_id is not null then
        insert into payment_provider_tax_location (
            connected_seller_id,
            fingerprint,
            payment_provider_id,
            provider_tax_location_id,
            venue_snapshot
        ) values (
            p_provider_object_account_id,
            p_performance_location_fingerprint,
            p_provider,
            p_provider_tax_location_id,
            v_purchase.venue_snapshot
        )
        on conflict (
            payment_provider_id,
            connected_seller_id,
            fingerprint
        ) do update
        set provider_tax_location_id = excluded.provider_tax_location_id;
    end if;

    -- Preserve the provider tax product for account-scoped reuse
    if p_provider_tax_product_id is not null then
        insert into payment_provider_tax_product (
            connected_seller_id,
            fingerprint,
            payment_provider_id,
            provider_tax_location_id,
            provider_tax_product_id,
            tax_code,
            title
        ) values (
            p_provider_object_account_id,
            p_provider_product_fingerprint,
            p_provider,
            p_provider_tax_location_id,
            p_provider_tax_product_id,
            v_purchase.provider_tax_code,
            v_purchase.ticket_title
        )
        on conflict (
            payment_provider_id,
            connected_seller_id,
            fingerprint
        ) do update
        set provider_tax_product_id = excluded.provider_tax_product_id;
    end if;

    -- Store the canonical Checkout session and immutable resource references
    update event_purchase
    set
        payment_provider_id = p_provider,
        performance_location_fingerprint = p_performance_location_fingerprint,
        provider_checkout_session_id = p_provider_checkout_session_id,
        provider_checkout_url = p_provider_checkout_url,
        provider_product_fingerprint = p_provider_product_fingerprint,
        provider_tax_location_id = p_provider_tax_location_id,
        provider_tax_product_id = p_provider_tax_product_id,
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id
    and provider_checkout_session_id is null;

end;
$$ language plpgsql;
