-- Caches a provider tax location by seller and normalized venue fingerprint.
create or replace function upsert_payment_provider_tax_location(
    p_payment_provider_id text,
    p_connected_seller_id text,
    p_fingerprint text,
    p_provider_tax_location_id text,
    p_venue_snapshot jsonb
)
returns void as $$
begin
    -- Store the current provider resource for the normalized venue
    insert into payment_provider_tax_location (
        connected_seller_id,
        fingerprint,
        payment_provider_id,
        provider_tax_location_id,
        venue_snapshot
    ) values (
        p_connected_seller_id,
        p_fingerprint,
        p_payment_provider_id,
        p_provider_tax_location_id,
        p_venue_snapshot
    )
    on conflict (
        payment_provider_id,
        connected_seller_id,
        fingerprint
    ) do update
    set
        provider_tax_location_id = excluded.provider_tax_location_id,
        venue_snapshot = excluded.venue_snapshot;
end;
$$ language plpgsql;
