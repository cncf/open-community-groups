-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return null when input is null
select is(
    escape_ilike_pattern(null),
    null,
    'Should return null when input is null'
);

-- Should leave regular text unchanged
select is(
    escape_ilike_pattern('alice'),
    'alice',
    'Should leave regular text unchanged'
);

-- Should escape ILIKE metacharacters and backslashes
select is(
    escape_ilike_pattern('user_1\100%'),
    'user\_1\\100\%',
    'Should escape ILIKE metacharacters and backslashes'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
