-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should generate slug with default length of 7
select is(
    length(generate_slug_from_source('legacy/group/42')),
    7,
    'Should generate slug with default length of 7'
);

-- Should generate slug with custom length
select is(
    length(generate_slug_from_source('legacy/group/42', 10)),
    10,
    'Should generate slug with custom length of 10'
);

-- Should only contain allowed characters (23456789abcdefghjkmnpqrstuvwxyz)
select ok(
    (
        select generate_slug_from_source('legacy/group/42', 100)
            ~ '^[23456789abcdefghjkmnpqrstuvwxyz]+$'
    ),
    'Should only contain allowed characters'
);

-- Should generate the same slug for the same source
select is(
    generate_slug_from_source('legacy/group/42'),
    generate_slug_from_source('legacy/group/42'),
    'Should generate the same slug for the same source'
);

-- Should treat case-sensitive input as different source
select isnt(
    generate_slug_from_source('legacy/group/42', 12),
    generate_slug_from_source('Legacy/group/42', 12),
    'Should treat case-sensitive input as different source'
);

-- Should generate different slugs for different sources
select isnt(
    generate_slug_from_source('legacy/group/42', 12),
    generate_slug_from_source('legacy/group/43', 12),
    'Should generate different slugs for different sources'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
