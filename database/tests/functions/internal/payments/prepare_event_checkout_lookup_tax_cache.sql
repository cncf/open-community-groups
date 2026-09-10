-- Tests looking up cached automatic-tax provider resources for a checkout.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Venue snapshots with and without a cached tax location
create temporary table test_venue (cached jsonb not null, uncached jsonb not null);
insert into test_venue values (
    '{"address": "1 Main St", "city": "Portland", "country_code": "US", "name": "Venue", "state_code": null, "state_name": null, "zip_code": "97201"}'::jsonb,
    '{"address": "2 Side St", "city": "Portland", "country_code": "US", "name": "Annex", "state_code": "OR", "state_name": "Oregon", "zip_code": "97201"}'::jsonb
);

-- Cached tax location of the seller for the cached venue
insert into payment_provider_tax_location (
    connected_seller_id,
    fingerprint,
    payment_provider_id,
    provider_tax_location_id,
    venue_snapshot
)
select
    'acct_tax_cache',
    encode(
        digest(
            convert_to('1 Main St', 'UTF8') || decode('00', 'hex')
            || convert_to('Portland', 'UTF8') || decode('00', 'hex')
            || convert_to('US', 'UTF8') || decode('00', 'hex')
            || convert_to('Venue', 'UTF8') || decode('00', 'hex')
            || convert_to('', 'UTF8') || decode('00', 'hex')
            || convert_to('97201', 'UTF8') || decode('00', 'hex'),
            'sha256'
        ),
        'hex'
    ),
    'stripe',
    'loc_tax_cache',
    cached
from test_venue;

-- Cached ticket product of the seller for that location and title
insert into payment_provider_tax_product (
    connected_seller_id,
    fingerprint,
    payment_provider_id,
    provider_tax_location_id,
    provider_tax_product_id,
    tax_code,
    title
)
values (
    'acct_tax_cache',
    encode(
        digest(
            convert_to('General admission', 'UTF8') || decode('00', 'hex')
            || convert_to('loc_tax_cache', 'UTF8') || decode('00', 'hex')
            || convert_to('txcd_50013001', 'UTF8') || decode('00', 'hex'),
            'sha256'
        ),
        'hex'
    ),
    'stripe',
    'loc_tax_cache',
    'prod_tax_cache',
    'txcd_50013001',
    'General admission'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the cached location and product for a known venue and title
select is(
    (
        select jsonb_build_object(
            'provider_tax_location_id', r.provider_tax_location_id,
            'provider_tax_product_id', r.provider_tax_product_id
        )
        from test_venue v
        cross join prepare_event_checkout_lookup_tax_cache('stripe', 'acct_tax_cache', v.cached, 'General admission') r
    ),
    '{"provider_tax_location_id": "loc_tax_cache", "provider_tax_product_id": "prod_tax_cache"}'::jsonb,
    'Should return the cached location and product for a known venue and title'
);

-- Should return the location without a product for an uncached title
select is(
    (
        select jsonb_build_object(
            'has_product_fingerprint', r.product_fingerprint is not null,
            'provider_tax_location_id', r.provider_tax_location_id,
            'provider_tax_product_id', r.provider_tax_product_id
        )
        from test_venue v
        cross join prepare_event_checkout_lookup_tax_cache('stripe', 'acct_tax_cache', v.cached, 'VIP') r
    ),
    '{"has_product_fingerprint": true, "provider_tax_location_id": "loc_tax_cache", "provider_tax_product_id": null}'::jsonb,
    'Should return the location without a product for an uncached title'
);

-- Should return only the location fingerprint for an uncached venue
select is(
    (
        select jsonb_build_object(
            'has_location_fingerprint', r.performance_location_fingerprint is not null,
            'product_fingerprint', r.product_fingerprint,
            'provider_tax_location_id', r.provider_tax_location_id,
            'provider_tax_product_id', r.provider_tax_product_id
        )
        from test_venue v
        cross join prepare_event_checkout_lookup_tax_cache('stripe', 'acct_tax_cache', v.uncached, 'General admission') r
    ),
    '{"has_location_fingerprint": true, "product_fingerprint": null, "provider_tax_location_id": null, "provider_tax_product_id": null}'::jsonb,
    'Should return only the location fingerprint for an uncached venue'
);

-- Should scope the cache to the connected seller
select is(
    (
        select r.provider_tax_location_id
        from test_venue v
        cross join prepare_event_checkout_lookup_tax_cache('stripe', 'acct_other', v.cached, 'General admission') r
    ),
    null::text,
    'Should scope the cache to the connected seller'
);

-- Should fingerprint the venue with an empty subdivision code when it is missing
select is(
    (
        select r.performance_location_fingerprint
        from test_venue v
        cross join prepare_event_checkout_lookup_tax_cache('stripe', 'acct_tax_cache', v.cached, 'General admission') r
    ),
    (select fingerprint from payment_provider_tax_location where provider_tax_location_id = 'loc_tax_cache'),
    'Should fingerprint the venue with an empty subdivision code when it is missing'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
