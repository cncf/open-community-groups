-- Tests resolving the manual Uses remaining override state of a discount code payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should disable the override when the payload clears Uses remaining
select is(
    resolve_event_discount_code_available_override(
        '{"available": 5, "available_cleared": true}'::jsonb,
        true
    ),
    false,
    'Should disable the override when the payload clears Uses remaining'
);

-- Should enable the override for a submitted count of zero
select is(
    resolve_event_discount_code_available_override('{"available": 0}'::jsonb),
    true,
    'Should enable the override for a submitted count of zero'
);

-- Should enable the override for a submitted count
select is(
    resolve_event_discount_code_available_override('{"available": 5}'::jsonb, false),
    true,
    'Should enable the override for a submitted count'
);

-- Should honor an explicit override flag over a submitted count
select is(
    resolve_event_discount_code_available_override(
        '{"available": 5, "available_override_active": false}'::jsonb,
        true
    ),
    false,
    'Should honor an explicit override flag over a submitted count'
);

-- Should honor an explicit override flag without a count
select is(
    resolve_event_discount_code_available_override(
        '{"available_override_active": true}'::jsonb,
        false
    ),
    true,
    'Should honor an explicit override flag without a count'
);

-- Should keep a prior disabled override when the payload is silent
select is(
    resolve_event_discount_code_available_override('{"code": "SAVE10"}'::jsonb, false),
    false,
    'Should keep a prior disabled override when the payload is silent'
);

-- Should keep a prior enabled override when the payload is silent
select is(
    resolve_event_discount_code_available_override('{"code": "SAVE10"}'::jsonb, true),
    true,
    'Should keep a prior enabled override when the payload is silent'
);

-- Should let clearing Uses remaining beat an explicit override flag
select is(
    resolve_event_discount_code_available_override(
        '{"available_cleared": true, "available_override_active": true}'::jsonb,
        true
    ),
    false,
    'Should let clearing Uses remaining beat an explicit override flag'
);

-- Should start new codes without an override when the payload is silent
select is(
    resolve_event_discount_code_available_override('{"code": "SAVE10"}'::jsonb),
    false,
    'Should start new codes without an override when the payload is silent'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
