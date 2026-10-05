-- Tests loading unexpired authentication sessions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set sessionExpiredID 'get-auth-session-expired'
\set sessionExpiringNowID 'get-auth-session-expiring-now'
\set sessionUnexpiredID 'get-auth-session-unexpired'
\set sessionUnknownID 'get-auth-session-unknown'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Session that expired one second ago
insert into auth_session (auth_session_id, data, expires_at)
values (:'sessionExpiredID', '{"state": "expired"}', current_timestamp - interval '1 second');

-- Session expiring at the current transaction timestamp
insert into auth_session (auth_session_id, data, expires_at)
values (:'sessionExpiringNowID', '{"state": "expiring-now"}', current_timestamp);

-- Session expiring in one hour
insert into auth_session (auth_session_id, data, expires_at)
values (:'sessionUnexpiredID', '{"state": "unexpired"}', current_timestamp + interval '1 hour');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should not return a session expiring exactly now
select is_empty(
    format($$select * from get_auth_session(%L)$$, :'sessionExpiringNowID'),
    'Should not return a session expiring exactly now'
);

-- Should not return an expired session
select is_empty(
    format($$select * from get_auth_session(%L)$$, :'sessionExpiredID'),
    'Should not return an expired session'
);

-- Should return an unexpired session
select results_eq(
    format($$select * from get_auth_session(%L)$$, :'sessionUnexpiredID'),
    $$values ('{"state": "unexpired"}'::jsonb, current_timestamp + interval '1 hour')$$,
    'Should return an unexpired session'
);

-- Should return nothing for an unknown session ID
select is_empty(
    format($$select * from get_auth_session(%L)$$, :'sessionUnknownID'),
    'Should return nothing for an unknown session ID'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
