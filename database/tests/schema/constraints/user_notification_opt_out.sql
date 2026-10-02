-- Tests user notification opt-out constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set duplicateUserID 'c0050000-0000-0000-0000-000000000001'
\set userCascadeID 'c0050000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User whose opt-out is duplicated
select fx_user(:'duplicateUserID');

-- User whose opt-out should cascade on user deletion
select fx_user(:'userCascadeID');

-- Opt-out used by duplicate rejection
insert into user_notification_opt_out (notification_category_id, user_id)
values ('badges', :'duplicateUserID');

-- Opt-out deleted through user cascade
insert into user_notification_opt_out (notification_category_id, user_id)
values ('new-events', :'userCascadeID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject duplicate opt-outs
select throws_ok(
    format(
        $$
            insert into user_notification_opt_out (notification_category_id, user_id)
            values ('badges', %L::uuid)
        $$,
        :'duplicateUserID'
    ),
    '23505',
    null,
    'Should reject duplicate opt-outs'
);

-- Should reject unknown categories
select throws_ok(
    format(
        $$
            insert into user_notification_opt_out (notification_category_id, user_id)
            values ('unknown-category', %L::uuid)
        $$,
        :'duplicateUserID'
    ),
    '23503',
    null,
    'Should reject unknown categories'
);

-- Should delete opt-outs when users are deleted
select lives_ok(
    format($$delete from "user" where user_id = %L::uuid$$, :'userCascadeID'),
    'Should delete users with opt-outs'
);
select is(
    (
        select count(*)::int
        from user_notification_opt_out
        where user_id = :'userCascadeID'
    ),
    0,
    'Should delete opt-outs when users are deleted'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
