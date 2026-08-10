-- Attaches an asynchronously created application fee to its direct-charge purchase.
create or replace function attach_application_fee_to_event_purchase(
    p_provider text,
    p_connected_seller_id text,
    p_provider_charge_id text,
    p_provider_application_fee_id text,
    p_amount_minor bigint
)
returns void as $$
declare
    v_purchase event_purchase;
begin
    -- Validate the required provider context and application-fee amount
    if nullif(btrim(p_connected_seller_id), '') is null
       or nullif(btrim(p_provider_charge_id), '') is null
       or nullif(btrim(p_provider_application_fee_id), '') is null then
        raise exception 'application fee is missing provider context';
    end if;

    if p_amount_minor is null or p_amount_minor <= 0 then
        raise exception 'application fee amount must be positive';
    end if;

    -- Lock and load the purchase through its immutable direct-charge scope
    select ep.*
    into v_purchase
    from event_purchase ep
    where ep.payment_provider_id = p_provider
    and ep.connected_seller_id = p_connected_seller_id
    and ep.provider_charge_id = p_provider_charge_id
    for update;

    if not found then
        raise exception 'direct-charge purchase not found for application fee';
    end if;

    -- Validate the purchase snapshot and idempotent provider attachment
    if v_purchase.provisional_platform_fee_amount_minor <> p_amount_minor then
        raise exception 'application fee amount does not match the purchase';
    end if;

    if v_purchase.provider_application_fee_id is not null
       and v_purchase.provider_application_fee_id <> p_provider_application_fee_id then
        raise exception 'purchase has a different provider application fee';
    end if;

    -- Persist the application-fee attachment
    update event_purchase
    set
        provider_application_fee_id = p_provider_application_fee_id,
        updated_at = current_timestamp
    where event_purchase_id = v_purchase.event_purchase_id;
end;
$$ language plpgsql;
