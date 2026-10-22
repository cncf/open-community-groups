-- Tests generating random slugs.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should generate slug with custom length of 10
select is(
    length(generate_slug(10)),
    10,
    'Should generate slug with custom length of 10'
);

-- Should only contain allowed characters (23456789abcdefghjkmnpqrstuvwxyz)
select ok(
    (select generate_slug(100) ~ '^[23456789abcdefghjkmnpqrstuvwxyz]+$'),
    'Should only contain allowed characters'
);

-- Should consistently generate 7-character slugs (no empty characters)
select ok(
    (
        select bool_and(length(generate_slug()) = 7)
        from generate_series(1, 100)
    ),
    'Should consistently generate 7-character slugs (no empty characters)'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
