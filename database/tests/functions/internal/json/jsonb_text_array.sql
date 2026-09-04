-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should convert JSON text arrays to SQL text arrays
select is(
    jsonb_text_array('["alpha", "beta"]'::jsonb),
    array['alpha', 'beta'],
    'Should convert JSON text arrays to SQL text arrays'
);

-- Should preserve empty arrays
select is(
    jsonb_text_array('[]'::jsonb),
    array[]::text[],
    'Should preserve empty arrays'
);

-- Should return null for SQL null
select is(
    jsonb_text_array(null),
    null::text[],
    'Should return null for SQL null'
);

-- Should return null for JSON null
select is(
    jsonb_text_array('null'::jsonb),
    null::text[],
    'Should return null for JSON null'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
