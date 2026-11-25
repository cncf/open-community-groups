-- Tests batched deletion of expired authentication sessions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set sessionActiveID 'delete-expired-auth-sessions-active'
\set sessionExpiredBoundaryID 'delete-expired-auth-sessions-expired-boundary'
\set sessionExpiredGraceID 'delete-expired-auth-sessions-expired-grace'
\set sessionExpiredNewerID 'delete-expired-auth-sessions-expired-newer'
\set sessionExpiredOldestID 'delete-expired-auth-sessions-expired-oldest'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active session that must remain untouched
insert into auth_session (auth_session_id, data, expires_at)
values (
    :'sessionActiveID',
    '{"state": "active"}',
    current_timestamp + interval '1 hour'
);

-- Session expiring at the 1-minute cleanup grace boundary
insert into auth_session (auth_session_id, data, expires_at)
values (
    :'sessionExpiredBoundaryID',
    '{"state": "expired-boundary"}',
    current_timestamp - interval '1 minute'
);

-- Recently expired session still within the 1-minute cleanup grace window
insert into auth_session (auth_session_id, data, expires_at)
values (
    :'sessionExpiredGraceID',
    '{"state": "expired-grace"}',
    current_timestamp - interval '30 seconds'
);

-- More recently expired session included in the first batch
insert into auth_session (auth_session_id, data, expires_at)
values (
    :'sessionExpiredNewerID',
    '{"state": "expired-newer"}',
    current_timestamp - interval '1 hour'
);

-- Oldest expired session included first in batch order
insert into auth_session (auth_session_id, data, expires_at)
values (
    :'sessionExpiredOldestID',
    '{"state": "expired-oldest"}',
    current_timestamp - interval '2 hours'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a batch size above the limit
select throws_ok(
    $$select delete_expired_auth_sessions(1001)$$,
    'P0001',
    'auth session cleanup batch size must be between 1 and 1000',
    'Should reject a batch size above the limit'
);

-- Should reject a negative batch size
select throws_ok(
    $$select delete_expired_auth_sessions(-1)$$,
    'P0001',
    'auth session cleanup batch size must be between 1 and 1000',
    'Should reject a negative batch size'
);

-- Should reject a null batch size
select throws_ok(
    $$select delete_expired_auth_sessions(null)$$,
    'P0001',
    'auth session cleanup batch size must be between 1 and 1000',
    'Should reject a null batch size'
);

-- Should reject a zero batch size
select throws_ok(
    $$select delete_expired_auth_sessions(0)$$,
    'P0001',
    'auth session cleanup batch size must be between 1 and 1000',
    'Should reject a zero batch size'
);

-- Should delete at most one bounded batch of oldest expired sessions
select is(
    delete_expired_auth_sessions(2),
    2,
    'Should delete at most one bounded batch of oldest expired sessions'
);

-- Should leave remaining expired, grace-window, and active sessions after the first batch
select results_eq(
    $$
        select auth_session_id
        from auth_session
        order by auth_session_id
    $$,
    format(
        $$values (%L), (%L), (%L)$$,
        :'sessionActiveID',
        :'sessionExpiredBoundaryID',
        :'sessionExpiredGraceID'
    ),
    'Should leave remaining expired, grace-window, and active sessions after the first batch'
);

-- Should delete the remaining boundary-expired session with the default batch size
select is(
    delete_expired_auth_sessions(),
    1,
    'Should delete the remaining boundary-expired session with the default batch size'
);

-- Should leave active and grace-window sessions after draining expired sessions
select results_eq(
    $$
        select auth_session_id
        from auth_session
        order by auth_session_id
    $$,
    format(
        $$values (%L), (%L)$$,
        :'sessionActiveID',
        :'sessionExpiredGraceID'
    ),
    'Should leave active and grace-window sessions after draining expired sessions'
);

-- Should return zero when no expired sessions remain
select is(
    delete_expired_auth_sessions(),
    0,
    'Should return zero when no expired sessions remain'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
