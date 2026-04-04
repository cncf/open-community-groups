-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set resourceID '00000000-0000-0000-0000-000000000001'
\set userID '00000000-0000-0000-0000-000000000041'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (user_id, auth_hash, email, username)
values (:'userID', 'hash', 'user@example.com', 'user');

-- Audit log row
insert into audit_log (action, actor_user_id, actor_username, resource_id, resource_type)
values ('community_updated', :'userID', 'user', :'resourceID', 'community');

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
    $$delete from "user" where user_id = '00000000-0000-0000-0000-000000000041'$$,
    'Should allow deleting referenced users'
);

-- Should keep actor snapshots after parent deletes
select results_eq(
    $$select actor_user_id::text, actor_username from audit_log$$,
    $$values ('00000000-0000-0000-0000-000000000041', 'user')$$,
    'Should keep actor snapshots after deleting referenced users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
