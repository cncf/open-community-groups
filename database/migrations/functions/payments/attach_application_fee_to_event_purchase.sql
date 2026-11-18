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
    -- Reject fees without the required provider context
    if nullif(btrim(p_connected_seller_id), '') is null
       or nullif(btrim(p_provider_charge_id), '') is null
       or nullif(btrim(p_provider_application_fee_id), '') is null then
        raise exception 'application fee is missing provider context';
    end if;

    -- Reject missing or non-positive application-fee amounts
    if p_amount_minor is null or p_amount_minor <= 0 then
        raise exception 'application fee amount must be positive';
    end if;

    -- Lock and load the purchase through its immutable direct-charge scope
    -- (a direct charge belongs to the seller account, which keys the charge index)
    select ep.*
    into v_purchase
    from event_purchase ep
    where ep.payment_provider_id = p_provider
    and ep.connected_seller_id = p_connected_seller_id
    and ep.provider_object_account_id = p_connected_seller_id
    and ep.provider_charge_id = p_provider_charge_id
    for update;

    -- Reject fees without a matching direct-charge purchase
    if not found then
        raise exception 'direct-charge purchase not found for application fee';
    end if;

    -- Reject fees whose amount differs from the purchase snapshot
    if v_purchase.provisional_platform_fee_amount_minor <> p_amount_minor then
        raise exception 'application fee amount does not match the purchase';
    end if;

    -- Reject a different application fee once one is attached
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
