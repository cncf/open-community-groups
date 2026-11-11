-- Tests pairing a dark image with the level that provides the light image.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the first level's dark image when it has both images
select is(
    paired_dark_image_url('light-1', 'dark-1', 'light-2', 'dark-2', 'light-3', 'dark-3'),
    'dark-1',
    'Should return the first level''s dark image when it has both images'
);

-- Should return null when the first level has a light image without a dark one
select is(
    paired_dark_image_url('light-1', null, 'light-2', 'dark-2', 'light-3', 'dark-3'),
    null::text,
    'Should return null when the first level has a light image without a dark one'
);

-- Should ignore a dark image on a level without a light image
select is(
    paired_dark_image_url(null, 'dark-1', 'light-2', 'dark-2', 'light-3', 'dark-3'),
    'dark-2',
    'Should ignore a dark image on a level without a light image'
);

-- Should return null when the second level provides a light image without a dark one
select is(
    paired_dark_image_url(null, null, 'light-2', null, 'light-3', 'dark-3'),
    null::text,
    'Should return null when the second level provides a light image without a dark one'
);

-- Should return the third level's dark image when it provides the light image
select is(
    paired_dark_image_url(null, null, null, 'dark-2', 'light-3', 'dark-3'),
    'dark-3',
    'Should return the third level''s dark image when it provides the light image'
);

-- Should return null when no level has a light image
select is(
    paired_dark_image_url(null, 'dark-1', null, 'dark-2', null, 'dark-3'),
    null::text,
    'Should return null when no level has a light image'
);

-- Should pair the dark image with a single level
select is(
    paired_dark_image_url('light-1', 'dark-1'),
    'dark-1',
    'Should pair the dark image with a single level'
);

-- Should ignore an orphan dark image when a single level is given
select is(
    paired_dark_image_url(null, 'dark-1'),
    null::text,
    'Should ignore an orphan dark image when a single level is given'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
