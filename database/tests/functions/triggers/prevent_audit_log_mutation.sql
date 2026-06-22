-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set resourceID 'ab090000-0000-0000-0000-000000000001'
\set userID 'ab090000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'audit-user-hash', 'audit-user@example.com', true, 'audit-user');

-- Audit log row
insert into audit_log (action, actor_user_id, actor_username, resource_id, resource_type)
values ('alliance_updated', :'userID', 'audit-user', :'resourceID', 'alliance');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject updates
select throws_ok(
    $$update audit_log set action = 'group_updated'$$,
    'audit_log is append-only',
    'Should reject updates to audit_log'
);

-- Should reject deletes
select throws_ok(
    $$delete from audit_log$$,
    'audit_log is append-only',
    'Should reject deletes from audit_log'
);

-- Should allow deleting referenced users
select lives_ok(
    format(
        $$delete from "user" where user_id = %L::uuid$$,
        :'userID'
    ),
    'Should allow deleting referenced users'
);

-- Should keep actor snapshots after parent deletes
select results_eq(
    $$select actor_user_id::text, actor_username from audit_log$$,
    format(
        $$values (%L::text, 'audit-user')$$,
        :'userID'
    ),
    'Should keep actor snapshots after deleting referenced users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
