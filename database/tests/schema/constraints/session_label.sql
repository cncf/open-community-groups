-- Tests session label constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c00a0000-0000-0000-0000-000000000001'
\set duplicateLabelID 'c00a0000-0000-0000-0000-000000000002'
\set duplicateSessionID 'c00a0000-0000-0000-0000-000000000003'
\set eventCategoryID 'c00a0000-0000-0000-0000-000000000004'
\set eventID 'c00a0000-0000-0000-0000-000000000005'
\set groupCategoryID 'c00a0000-0000-0000-0000-000000000006'
\set groupID 'c00a0000-0000-0000-0000-000000000007'
\set labelCascadeLabelID 'c00a0000-0000-0000-0000-000000000008'
\set labelCascadeSessionID 'c00a0000-0000-0000-0000-000000000009'
\set missingLabelID 'c00a0000-0000-0000-0000-000000000010'
\set missingSessionID 'c00a0000-0000-0000-0000-000000000011'
\set sessionCascadeLabelID 'c00a0000-0000-0000-0000-000000000012'
\set sessionCascadeSessionID 'c00a0000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the event with sessions
select fx_community(:'communityID');

-- Event category used by the event with sessions
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the event group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the event with sessions
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event containing the labeled sessions
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Label linked twice by duplicate rejection
insert into event_label (event_label_id, color, event_id, name)
values (:'duplicateLabelID', '#DBEAFE', :'eventID', 'Duplicate');

-- Label deleted through label cascade
insert into event_label (event_label_id, color, event_id, name)
values (:'labelCascadeLabelID', '#DBEAFE', :'eventID', 'Label Cascade');

-- Label whose link is deleted through session cascade
insert into event_label (event_label_id, color, event_id, name)
values (:'sessionCascadeLabelID', '#DBEAFE', :'eventID', 'Session Cascade');

-- Session whose label link is duplicated
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'duplicateSessionID', :'eventID', 'Duplicate Session', 'in-person', '2030-01-01 10:00:00+00');

-- Session whose label link is deleted through label cascade
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'labelCascadeSessionID', :'eventID', 'Label Cascade Session', 'in-person', '2030-01-01 11:00:00+00');

-- Session deleted through session cascade
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'sessionCascadeSessionID', :'eventID', 'Session Cascade Session', 'in-person', '2030-01-01 12:00:00+00');

-- Link used by duplicate rejection
insert into session_label (event_label_id, session_id)
values (:'duplicateLabelID', :'duplicateSessionID');

-- Link deleted through label cascade
insert into session_label (event_label_id, session_id)
values (:'labelCascadeLabelID', :'labelCascadeSessionID');

-- Link deleted through session cascade
insert into session_label (event_label_id, session_id)
values (:'sessionCascadeLabelID', :'sessionCascadeSessionID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should delete session labels when labels are deleted
select lives_ok(
    format($$delete from event_label where event_label_id = %L::uuid$$, :'labelCascadeLabelID'),
    'Should delete labels linked to sessions'
);
select is(
    (
        select count(*)::int
        from session_label
        where session_id = :'labelCascadeSessionID'
    ),
    0,
    'Should delete session labels when labels are deleted'
);
select is(
    (
        select count(*)::int
        from session
        where session_id = :'labelCascadeSessionID'
    ),
    1,
    'Should keep sessions when their labels are deleted'
);

-- Should delete session labels when sessions are deleted
select lives_ok(
    format($$delete from session where session_id = %L::uuid$$, :'sessionCascadeSessionID'),
    'Should delete sessions with labels'
);
select is(
    (
        select count(*)::int
        from session_label
        where event_label_id = :'sessionCascadeLabelID'
    ),
    0,
    'Should delete session labels when sessions are deleted'
);
select is(
    (
        select count(*)::int
        from event_label
        where event_label_id = :'sessionCascadeLabelID'
    ),
    1,
    'Should keep labels when their sessions are deleted'
);

-- Should reject duplicate session labels
select throws_ok(
    format(
        $$
            insert into session_label (event_label_id, session_id)
            values (%L::uuid, %L::uuid)
        $$,
        :'duplicateLabelID',
        :'duplicateSessionID'
    ),
    '23505',
    null,
    'Should reject duplicate session labels'
);

-- Should reject session labels for missing labels
select throws_ok(
    format(
        $$
            insert into session_label (event_label_id, session_id)
            values (%L::uuid, %L::uuid)
        $$,
        :'missingLabelID',
        :'duplicateSessionID'
    ),
    '23503',
    null,
    'Should reject session labels for missing labels'
);

-- Should reject session labels for missing sessions
select throws_ok(
    format(
        $$
            insert into session_label (event_label_id, session_id)
            values (%L::uuid, %L::uuid)
        $$,
        :'duplicateLabelID',
        :'missingSessionID'
    ),
    '23503',
    null,
    'Should reject session labels for missing sessions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
