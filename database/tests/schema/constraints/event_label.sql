-- Tests event label constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cascadeEventID 'c0080000-0000-0000-0000-000000000001'
\set cascadeLabelID 'c0080000-0000-0000-0000-000000000002'
\set communityID 'c0080000-0000-0000-0000-000000000003'
\set eventCategoryID 'c0080000-0000-0000-0000-000000000004'
\set eventID 'c0080000-0000-0000-0000-000000000005'
\set existingLabelID 'c0080000-0000-0000-0000-000000000006'
\set groupCategoryID 'c0080000-0000-0000-0000-000000000007'
\set groupID 'c0080000-0000-0000-0000-000000000008'
\set missingEventID 'c0080000-0000-0000-0000-000000000009'
\set otherEventID 'c0080000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the labeled events
select fx_community(:'communityID');

-- Event category used by the labeled events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the labeled events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the labeled events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose label is deleted through event cascade
select fx_event(:'cascadeEventID', :'groupID', :'eventCategoryID');

-- Event receiving the labels written by the constraint scenarios
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event reusing an existing label name
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');

-- Label deleted through event cascade
insert into event_label (event_label_id, color, event_id, name)
values (:'cascadeLabelID', '#DBEAFE', :'cascadeEventID', 'Cascade');

-- Label whose name is duplicated
insert into event_label (event_label_id, color, event_id, name)
values (:'existingLabelID', '#DBEAFE', :'eventID', 'Backend');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept the same label name in different events
select lives_ok(
    format(
        $$
            insert into event_label (color, event_id, name)
            values ('#FEE2E2', %L::uuid, 'Backend')
        $$,
        :'otherEventID'
    ),
    'Should accept the same label name in different events'
);

-- Should define label name uniqueness as deferrable and initially immediate
select is(
    (
        select jsonb_build_object(
            'condeferrable', condeferrable,
            'condeferred', condeferred
        )
        from pg_constraint
        where conname = 'event_label_event_id_name_key'
        and conrelid = 'event_label'::regclass
    ),
    jsonb_build_object(
        'condeferrable', true,
        'condeferred', false
    ),
    'Should define label name uniqueness as deferrable and initially immediate'
);

-- Should delete labels when events are deleted
select lives_ok(
    format($$delete from event where event_id = %L::uuid$$, :'cascadeEventID'),
    'Should delete events with labels'
);
select is(
    (
        select count(*)::int
        from event_label
        where event_label_id = :'cascadeLabelID'
    ),
    0,
    'Should delete labels when events are deleted'
);

-- Should reject blank label names
select throws_ok(
    format(
        $$
            insert into event_label (color, event_id, name)
            values ('#FEE2E2', %L::uuid, '   ')
        $$,
        :'eventID'
    ),
    '23514',
    null,
    'Should reject blank label names'
);

-- Should reject duplicate label names in the same event
select throws_ok(
    format(
        $$
            insert into event_label (color, event_id, name)
            values ('#FEE2E2', %L::uuid, 'Backend')
        $$,
        :'eventID'
    ),
    '23505',
    null,
    'Should reject duplicate label names in the same event'
);

-- Should reject label names longer than 80 characters
select throws_ok(
    format(
        $$
            insert into event_label (color, event_id, name)
            values ('#FEE2E2', %L::uuid, repeat('a', 81))
        $$,
        :'eventID'
    ),
    '23514',
    null,
    'Should reject label names longer than 80 characters'
);

-- Should reject labels for missing events
select throws_ok(
    format(
        $$
            insert into event_label (color, event_id, name)
            values ('#FEE2E2', %L::uuid, 'Missing')
        $$,
        :'missingEventID'
    ),
    '23503',
    null,
    'Should reject labels for missing events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
