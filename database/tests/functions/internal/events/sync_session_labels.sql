-- Tests replacing the labels linked to a session.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set clearEmptySessionID '1abe2000-0000-0000-0000-000000000001'
\set clearNullSessionID '1abe2000-0000-0000-0000-000000000002'
\set communityID '1abe2000-0000-0000-0000-000000000003'
\set eventCategoryID '1abe2000-0000-0000-0000-000000000004'
\set eventID '1abe2000-0000-0000-0000-000000000005'
\set eventOtherID '1abe2000-0000-0000-0000-000000000006'
\set foreignLabelSessionID '1abe2000-0000-0000-0000-000000000007'
\set groupCategoryID '1abe2000-0000-0000-0000-000000000008'
\set groupID '1abe2000-0000-0000-0000-000000000009'
\set label1ID '1abe2000-0000-0000-0000-00000000000a'
\set label2ID '1abe2000-0000-0000-0000-00000000000b'
\set label3ID '1abe2000-0000-0000-0000-00000000000c'
\set labelOtherID '1abe2000-0000-0000-0000-00000000000d'
\set otherSessionID '1abe2000-0000-0000-0000-00000000000e'
\set replaceSessionID '1abe2000-0000-0000-0000-00000000000f'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the events with sessions
select fx_community(:'communityID');

-- Event category used by the events with sessions
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the events with sessions
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose sessions are labeled
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event owning the session and label used by mismatch scenarios
select fx_event(:'eventOtherID', :'groupID', :'eventCategoryID');

-- First label of the event
insert into event_label (event_label_id, color, event_id, name)
values (:'label1ID', '#DBEAFE', :'eventID', 'Track / Backend');

-- Second label of the event
insert into event_label (event_label_id, color, event_id, name)
values (:'label2ID', '#FEE2E2', :'eventID', 'Track / Frontend');

-- Third label of the event
insert into event_label (event_label_id, color, event_id, name)
values (:'label3ID', '#CCFBF1', :'eventID', 'Track / Ops');

-- Label of the other event
insert into event_label (event_label_id, color, event_id, name)
values (:'labelOtherID', '#CCFBF1', :'eventOtherID', 'Track / Other');

-- Session cleared with an empty payload
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'clearEmptySessionID', :'eventID', 'Clear Empty', 'in-person', '2030-01-01 10:00:00+00');

-- Session cleared with a null payload
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'clearNullSessionID', :'eventID', 'Clear Null', 'in-person', '2030-01-01 11:00:00+00');

-- Session receiving a label from another event
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'foreignLabelSessionID', :'eventID', 'Foreign Label', 'in-person', '2030-01-01 12:00:00+00');

-- Session belonging to the other event
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'otherSessionID', :'eventOtherID', 'Other', 'in-person', '2030-01-01 13:00:00+00');

-- Session whose labels are replaced
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'replaceSessionID', :'eventID', 'Replace', 'in-person', '2030-01-01 14:00:00+00');

-- Label linked to the session cleared with an empty payload
insert into session_label (event_label_id, session_id)
values (:'label1ID', :'clearEmptySessionID');

-- Label linked to the session cleared with a null payload
insert into session_label (event_label_id, session_id)
values (:'label1ID', :'clearNullSessionID');

-- Label linked to the session receiving a foreign label
insert into session_label (event_label_id, session_id)
values (:'label1ID', :'foreignLabelSessionID');

-- Label linked to the other event session
insert into session_label (event_label_id, session_id)
values (:'labelOtherID', :'otherSessionID');

-- Label replaced on the session
insert into session_label (event_label_id, session_id)
values (:'label1ID', :'replaceSessionID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should clear labels when the payload is empty
select lives_ok(
    format(
        $$select sync_session_labels(%L::uuid, %L::uuid, array[]::uuid[])$$,
        :'clearEmptySessionID',
        :'eventID'
    ),
    'Should clear labels when the payload is empty'
);
select is(
    (select count(*)::int from session_label where session_id = :'clearEmptySessionID'),
    0,
    'Should remove existing labels for an empty payload'
);

-- Should clear labels when the payload is null
select lives_ok(
    format(
        $$select sync_session_labels(%L::uuid, %L::uuid, null)$$,
        :'clearNullSessionID',
        :'eventID'
    ),
    'Should clear labels when the payload is null'
);
select is(
    (select count(*)::int from session_label where session_id = :'clearNullSessionID'),
    0,
    'Should remove existing labels for a null payload'
);

-- Should reject labels from another event
select throws_ok(
    format(
        $$select sync_session_labels(%L::uuid, %L::uuid, array[%L::uuid, %L::uuid])$$,
        :'foreignLabelSessionID',
        :'eventID',
        :'label2ID',
        :'labelOtherID'
    ),
    'OCG01',
    'invalid event labels',
    'Should reject labels from another event'
);
select results_eq(
    format(
        $$select event_label_id from session_label where session_id = %L::uuid$$,
        :'foreignLabelSessionID'
    ),
    format($$values (%L::uuid)$$, :'label1ID'),
    'Should keep labels when rejecting labels from another event'
);

-- Should reject mismatched session and event IDs
select throws_ok(
    format(
        $$select sync_session_labels(%L::uuid, %L::uuid, array[%L::uuid])$$,
        :'otherSessionID',
        :'eventID',
        :'label1ID'
    ),
    'OCG01',
    'session not found',
    'Should reject mismatched session and event IDs'
);
select results_eq(
    format(
        $$select event_label_id from session_label where session_id = %L::uuid$$,
        :'otherSessionID'
    ),
    format($$values (%L::uuid)$$, :'labelOtherID'),
    'Should leave mismatched session labels unchanged'
);

-- Should replace labels and remove duplicates
select lives_ok(
    format(
        $$select sync_session_labels(%L::uuid, %L::uuid, array[%L::uuid, %L::uuid, %L::uuid])$$,
        :'replaceSessionID',
        :'eventID',
        :'label3ID',
        :'label2ID',
        :'label3ID'
    ),
    'Should replace labels and remove duplicates'
);
select results_eq(
    format(
        $$
            select event_label_id
            from session_label
            where session_id = %L::uuid
            order by event_label_id
        $$,
        :'replaceSessionID'
    ),
    format($$values (%L::uuid), (%L::uuid)$$, :'label2ID', :'label3ID'),
    'Should store the replacement labels once'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
