-- Tests notification category constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject blank display names
select throws_ok(
    $$
        insert into notification_category (notification_category_id, display_name, group_mutable)
        values ('blank-display-name-test', '', false)
    $$,
    '23514',
    'new row for relation "notification_category" violates check constraint "notification_category_display_name_check"',
    'Should reject blank display names'
);

-- Should reject duplicate display names
select throws_ok(
    $$
        insert into notification_category (notification_category_id, display_name, group_mutable)
        values ('duplicate-display-name-test', 'Badges', true)
    $$,
    '23505',
    null,
    'Should reject duplicate display names'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
