-- Tests caching provider tax locations by normalized venue fingerprint.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set connectedSellerID 'acct_tax_location_test'
\set fingerprint 'venue-fingerprint'
\set initialProviderTaxLocationID 'taxloc_initial'
\set replacementProviderTaxLocationID 'taxloc_replacement'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should insert a provider tax location for a new fingerprint
select lives_ok(
    format($$
        select upsert_payment_provider_tax_location(
            'stripe',
            %L,
            %L,
            %L,
            '{"city": "Madrid", "state_code": null}'::jsonb
        )
    $$, :'connectedSellerID', :'fingerprint', :'initialProviderTaxLocationID'),
    'Should insert a provider tax location for a new fingerprint'
);

select results_eq(
    format($$
        select
            connected_seller_id,
            fingerprint,
            payment_provider_id,
            provider_tax_location_id,
            venue_snapshot
        from payment_provider_tax_location
        where connected_seller_id = %L
    $$, :'connectedSellerID'),
    format($$
        values (
            %L::text,
            %L::text,
            'stripe'::text,
            %L::text,
            '{"city": "Madrid", "state_code": null}'::jsonb
        )
    $$, :'connectedSellerID', :'fingerprint', :'initialProviderTaxLocationID'),
    'Should persist the inserted provider tax location'
);

-- Should update the provider resource for a matching fingerprint
select lives_ok(
    format($$
        select upsert_payment_provider_tax_location(
            'stripe',
            %L,
            %L,
            %L,
            '{"city": "Málaga", "state_code": "MA"}'::jsonb
        )
    $$, :'connectedSellerID', :'fingerprint', :'replacementProviderTaxLocationID'),
    'Should update the provider resource for a matching fingerprint'
);

select results_eq(
    format($$
        select
            connected_seller_id,
            fingerprint,
            payment_provider_id,
            provider_tax_location_id,
            venue_snapshot
        from payment_provider_tax_location
        where connected_seller_id = %L
    $$, :'connectedSellerID'),
    format($$
        values (
            %L::text,
            %L::text,
            'stripe'::text,
            %L::text,
            '{"city": "Málaga", "state_code": "MA"}'::jsonb
        )
    $$, :'connectedSellerID', :'fingerprint', :'replacementProviderTaxLocationID'),
    'Should persist the replacement provider tax location and venue snapshot'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
