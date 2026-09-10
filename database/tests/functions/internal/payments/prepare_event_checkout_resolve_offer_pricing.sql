-- Tests resolving checkout pricing from an admission offer snapshot.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set discountCodeID 'f3030000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Offer snapshots with and without a discount code
create temporary table test_offer (discounted admission_offer not null, plain admission_offer not null);
insert into test_offer values (
    jsonb_populate_record(null::admission_offer, format('{
        "amount_minor": 2000,
        "currency_code": "USD",
        "discount_amount_minor": 500,
        "discount_code": " save10 ",
        "event_discount_code_id": "%s",
        "ticket_title": "General"
    }', :'discountCodeID')::jsonb),
    jsonb_populate_record(null::admission_offer, '{
        "amount_minor": 2500,
        "currency_code": "EUR",
        "ticket_title": "Early Bird"
    }'::jsonb)
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reuse the snapshotted code and pricing when the code is omitted
select is(
    (
        select to_jsonb(r)
        from test_offer t
        cross join prepare_event_checkout_resolve_offer_pricing(t.discounted, null) r
    ),
    format('{
        "currency_code": "USD",
        "discount_amount_minor": 500,
        "discount_code": "SAVE10",
        "event_discount_code_id": "%s",
        "final_amount_minor": 2000,
        "price_locked": false,
        "ticket_title": "General"
    }', :'discountCodeID')::jsonb,
    'Should reuse the snapshotted code and pricing when the code is omitted'
);

-- Should accept the same normalized code as the snapshot
select is(
    (
        select jsonb_build_object('discount_code', r.discount_code, 'price_locked', r.price_locked)
        from test_offer t
        cross join prepare_event_checkout_resolve_offer_pricing(t.discounted, 'SAVE10') r
    ),
    '{"discount_code": "SAVE10", "price_locked": false}'::jsonb,
    'Should accept the same normalized code as the snapshot'
);

-- Should report a locked price when another code is submitted
select is(
    (
        select to_jsonb(r)
        from test_offer t
        cross join prepare_event_checkout_resolve_offer_pricing(t.discounted, 'OTHER') r
    ),
    '{
        "currency_code": null,
        "discount_amount_minor": null,
        "discount_code": null,
        "event_discount_code_id": null,
        "final_amount_minor": null,
        "price_locked": true,
        "ticket_title": null
    }'::jsonb,
    'Should report a locked price when another code is submitted'
);

-- Should report a locked price when a code is submitted for an undiscounted snapshot
select is(
    (
        select r.price_locked
        from test_offer t
        cross join prepare_event_checkout_resolve_offer_pricing(t.plain, 'SAVE10') r
    ),
    true,
    'Should report a locked price when a code is submitted for an undiscounted snapshot'
);

-- Should return the undiscounted snapshot without a code
select is(
    (
        select to_jsonb(r)
        from test_offer t
        cross join prepare_event_checkout_resolve_offer_pricing(t.plain, null) r
    ),
    '{
        "currency_code": "EUR",
        "discount_amount_minor": null,
        "discount_code": null,
        "event_discount_code_id": null,
        "final_amount_minor": 2500,
        "price_locked": false,
        "ticket_title": "Early Bird"
    }'::jsonb,
    'Should return the undiscounted snapshot without a code'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
