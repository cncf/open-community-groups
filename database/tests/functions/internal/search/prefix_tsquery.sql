-- Tests building prefix-matching full-text queries.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should match every lexeme as a prefix
select is(
    prefix_tsquery('simple', 'kube meet'),
    $$'kube':* & 'meet':*$$::tsquery,
    'Should match every lexeme as a prefix'
);

-- Should honor the text search configuration
select is(
    prefix_tsquery('english', 'running'),
    $$'run':*$$::tsquery,
    'Should honor the text search configuration'
);

-- Should match partially typed words
select ok(
    to_tsvector('simple', 'Kubernetes Meetup') @@ prefix_tsquery('simple', 'kuber'),
    'Should match partially typed words'
);

-- Should return null for null input
select is(
    prefix_tsquery('simple', null),
    null::tsquery,
    'Should return null for null input'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
