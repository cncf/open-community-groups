-- Tests taking the event-user enrollment advisory lock.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set eventID '10cd0000-0000-0000-0000-000000000001'
\set userID '10cd0000-0000-0000-0000-000000000002'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should hold the event-user advisory lock
-- Take the lock within this scenario before reading pg_locks
select 1 as "eventUserLocked" from lock_event_user(:'eventID', :'userID') \gset

select ok(
    exists (
        select 1
        from pg_locks l
        where l.locktype = 'advisory'
        and l.pid = pg_backend_pid()
        and l.classid = hashtext(:'eventID'::text)::oid
        and l.objid = hashtext(:'userID'::text)::oid
        and l.objsubid = 2
        and l.granted
    ),
    'Should hold the event-user advisory lock'
);

-- Should take the lock again within the same transaction
select lives_ok(
    format($$select lock_event_user(%L::uuid, %L::uuid)$$, :'eventID', :'userID'),
    'Should take the lock again within the same transaction'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
