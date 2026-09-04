-- Looks up the cached automatic-tax provider resources of a connected seller
-- for a checkout: the tax location matching the venue fingerprint and, when
-- one exists, the ticket product matching the location and ticket title.
-- Missing cache entries return null identifiers together with the fingerprints
-- the server uses to create and cache them.
create or replace function prepare_event_checkout_lookup_tax_cache(
    p_payment_provider_id text,
    p_connected_seller_id text,
    p_venue_snapshot jsonb,
    p_ticket_title text
)
returns table (
    performance_location_fingerprint text,
    product_fingerprint text,
    provider_tax_location_id text,
    provider_tax_product_id text
) as $$
declare
    v_performance_location_fingerprint text;
    v_product_fingerprint text;
    v_provider_tax_location_id text;
    v_provider_tax_product_id text;
begin
    -- Fingerprint the taxable performance location
    v_performance_location_fingerprint := encode(
        digest(
            convert_to(p_venue_snapshot->>'address', 'UTF8') || decode('00', 'hex')
            || convert_to(p_venue_snapshot->>'city', 'UTF8') || decode('00', 'hex')
            || convert_to(p_venue_snapshot->>'country_code', 'UTF8') || decode('00', 'hex')
            || convert_to(p_venue_snapshot->>'name', 'UTF8') || decode('00', 'hex')
            || convert_to(coalesce(p_venue_snapshot->>'state_code', ''), 'UTF8') || decode('00', 'hex')
            || convert_to(p_venue_snapshot->>'zip_code', 'UTF8') || decode('00', 'hex'),
            'sha256'
        ),
        'hex'
    );

    -- Reuse the cached tax location of the seller for that fingerprint
    select pptl.provider_tax_location_id
    into v_provider_tax_location_id
    from payment_provider_tax_location pptl
    where pptl.payment_provider_id = p_payment_provider_id
    and pptl.connected_seller_id = p_connected_seller_id
    and pptl.fingerprint = v_performance_location_fingerprint;

    -- Reuse a cached ticket product for the resolved performance location
    if v_provider_tax_location_id is not null then
        v_product_fingerprint := encode(
            digest(
                convert_to(left(p_ticket_title, 250), 'UTF8') || decode('00', 'hex')
                || convert_to(v_provider_tax_location_id, 'UTF8') || decode('00', 'hex')
                || convert_to('txcd_50013001', 'UTF8') || decode('00', 'hex'),
                'sha256'
            ),
            'hex'
        );

        select pptp.provider_tax_product_id
        into v_provider_tax_product_id
        from payment_provider_tax_product pptp
        where pptp.payment_provider_id = p_payment_provider_id
        and pptp.connected_seller_id = p_connected_seller_id
        and pptp.fingerprint = v_product_fingerprint;
    end if;

    -- Return the fingerprints and cached identifiers
    return query select
        v_performance_location_fingerprint,
        v_product_fingerprint,
        v_provider_tax_location_id,
        v_provider_tax_product_id;
end;
$$ language plpgsql stable;
