-- Tests building the site-root-relative path of a public event page.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should fall back to the group slug without a pretty slug
select is(
    event_public_path('community-a', 'abc1234', null, 'event-a'),
    '/community-a/group/abc1234/event/event-a',
    'Should fall back to the group slug without a pretty slug'
);

-- Should prefer the group pretty slug when configured
select is(
    event_public_path('community-a', 'abc1234', 'group-a', 'event-a'),
    '/community-a/group/group-a/event/event-a',
    'Should prefer the group pretty slug when configured'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
