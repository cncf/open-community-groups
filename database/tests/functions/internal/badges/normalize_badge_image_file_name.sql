-- Tests normalizing badge image values to the stored gallery file name.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep a bare file name unchanged
select is(
    normalize_badge_image_file_name('x.png'),
    'x.png',
    'Should keep a bare file name unchanged'
);

-- Should return null for a null value
select is(
    normalize_badge_image_file_name(null),
    null::text,
    'Should return null for a null value'
);

-- Should return null for an empty value
select is(
    normalize_badge_image_file_name(''),
    null::text,
    'Should return null for an empty value'
);

-- Should return null for a whitespace value
select is(
    normalize_badge_image_file_name('   '),
    null::text,
    'Should return null for a whitespace value'
);

-- Should strip the badges image path prefix
select is(
    normalize_badge_image_file_name('/images/badges/x.png'),
    'x.png',
    'Should strip the badges image path prefix'
);

-- Should strip the images path prefix
select is(
    normalize_badge_image_file_name('/images/x.png'),
    'x.png',
    'Should strip the images path prefix'
);

-- Should trim whitespace around the prefixed value
select is(
    normalize_badge_image_file_name('  /images/badges/x.png  '),
    'x.png',
    'Should trim whitespace around the prefixed value'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
