-- Tests synchronizing the labels of an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(26);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cascadeEventID '3a310000-0000-0000-0000-000000000001'
\set cascadeKeepLabelID '3a310000-0000-0000-0000-000000000002'
\set cascadeProposalID '3a310000-0000-0000-0000-000000000003'
\set cascadeRemoveLabelID '3a310000-0000-0000-0000-000000000004'
\set cascadeSessionID '3a310000-0000-0000-0000-000000000005'
\set cascadeSubmissionID '3a310000-0000-0000-0000-000000000006'
\set clearEventID '3a310000-0000-0000-0000-000000000007'
\set clearLabelID '3a310000-0000-0000-0000-000000000008'
\set communityID '3a310000-0000-0000-0000-000000000009'
\set duplicateEventID '3a310000-0000-0000-0000-00000000000a'
\set duplicateLabelAID '3a310000-0000-0000-0000-00000000000b'
\set duplicateLabelBID '3a310000-0000-0000-0000-00000000000c'
\set eventCategoryID '3a310000-0000-0000-0000-00000000000d'
\set foreignEventID '3a310000-0000-0000-0000-00000000000e'
\set foreignEventLabelID '3a310000-0000-0000-0000-00000000000f'
\set foreignOwnerEventID '3a310000-0000-0000-0000-000000000010'
\set foreignOwnerLabelID '3a310000-0000-0000-0000-000000000011'
\set groupCategoryID '3a310000-0000-0000-0000-000000000012'
\set groupID '3a310000-0000-0000-0000-000000000013'
\set insertEventID '3a310000-0000-0000-0000-000000000014'
\set insertLabelID '3a310000-0000-0000-0000-000000000015'
\set nullEventID '3a310000-0000-0000-0000-000000000016'
\set recreateEventID '3a310000-0000-0000-0000-000000000017'
\set recreateNewLabelID '3a310000-0000-0000-0000-000000000018'
\set recreateOldLabelID '3a310000-0000-0000-0000-000000000019'
\set renameEventID '3a310000-0000-0000-0000-00000000001a'
\set renameLabelID '3a310000-0000-0000-0000-00000000001b'
\set retryEventID '3a310000-0000-0000-0000-00000000001c'
\set retryLabelID '3a310000-0000-0000-0000-00000000001d'
\set rotateEventID '3a310000-0000-0000-0000-00000000001e'
\set rotateLabel1ID '3a310000-0000-0000-0000-00000000001f'
\set rotateLabel2ID '3a310000-0000-0000-0000-000000000020'
\set rotateLabel3ID '3a310000-0000-0000-0000-000000000021'
\set staleEventID '3a310000-0000-0000-0000-000000000022'
\set staleLabelID '3a310000-0000-0000-0000-000000000023'
\set staleMissingLabelID '3a310000-0000-0000-0000-000000000024'
\set swapEventID '3a310000-0000-0000-0000-000000000025'
\set swapLeftLabelID '3a310000-0000-0000-0000-000000000026'
\set swapRightLabelID '3a310000-0000-0000-0000-000000000027'
\set userID '3a310000-0000-0000-0000-000000000028'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the labeled events
select fx_community(:'communityID');

-- Speaker who owns the proposal linked to a removed label
select fx_user(:'userID');

-- Event category used by the labeled events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the labeled events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Proposal whose submission is linked to a removed label
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'cascadeProposalID',
    'Cascade proposal description',
    interval '30 minutes',
    'beginner',
    'Cascade Proposal',
    :'userID'
);

-- Group hosting the labeled events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose removed label is linked to a session and a submission
select fx_event(:'cascadeEventID', :'groupID', :'eventCategoryID');

-- Event whose labels are all removed
select fx_event(:'clearEventID', :'groupID', :'eventCategoryID');

-- Event receiving duplicate final label names
select fx_event(:'duplicateEventID', :'groupID', :'eventCategoryID');

-- Event receiving a label owned by another event
select fx_event(:'foreignEventID', :'groupID', :'eventCategoryID');

-- Event owning the label claimed by another event
select fx_event(:'foreignOwnerEventID', :'groupID', :'eventCategoryID');

-- Event receiving its first label
select fx_event(:'insertEventID', :'groupID', :'eventCategoryID');

-- Event receiving a null labels payload
select fx_event(:'nullEventID', :'groupID', :'eventCategoryID');

-- Event replacing a label with a new label of the same name
select fx_event(:'recreateEventID', :'groupID', :'eventCategoryID');

-- Event whose label is renamed and recolored
select fx_event(:'renameEventID', :'groupID', :'eventCategoryID');

-- Event retrying a new label that was already stored
select fx_event(:'retryEventID', :'groupID', :'eventCategoryID');

-- Event rotating names across three labels
select fx_event(:'rotateEventID', :'groupID', :'eventCategoryID');

-- Event receiving a stale label identifier
select fx_event(:'staleEventID', :'groupID', :'eventCategoryID');

-- Event swapping two label names
select fx_event(:'swapEventID', :'groupID', :'eventCategoryID');

-- Submission linked to a removed label
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'cascadeSubmissionID', :'cascadeEventID', :'cascadeProposalID', 'not-reviewed');

-- Label kept on the event with linked items
insert into event_label (event_label_id, color, event_id, name)
values (:'cascadeKeepLabelID', '#DBEAFE', :'cascadeEventID', 'Keep');

-- Label removed from the event with linked items
insert into event_label (event_label_id, color, event_id, name)
values (:'cascadeRemoveLabelID', '#FEE2E2', :'cascadeEventID', 'Remove');

-- Label removed by an empty payload
insert into event_label (event_label_id, color, event_id, name)
values (:'clearLabelID', '#DBEAFE', :'clearEventID', 'Clear');

-- First label renamed to a duplicate name
insert into event_label (event_label_id, color, event_id, name)
values (:'duplicateLabelAID', '#DBEAFE', :'duplicateEventID', 'Alpha');

-- Second label renamed to a duplicate name
insert into event_label (event_label_id, color, event_id, name)
values (:'duplicateLabelBID', '#FEE2E2', :'duplicateEventID', 'Beta');

-- Label kept when a foreign label is rejected
insert into event_label (event_label_id, color, event_id, name)
values (:'foreignEventLabelID', '#DBEAFE', :'foreignEventID', 'Own');

-- Label owned by another event
insert into event_label (event_label_id, color, event_id, name)
values (:'foreignOwnerLabelID', '#FEE2E2', :'foreignOwnerEventID', 'Owned');

-- Label replaced by a new label of the same name
insert into event_label (event_label_id, color, event_id, name)
values (:'recreateOldLabelID', '#DBEAFE', :'recreateEventID', 'Alpha');

-- Label renamed and recolored
insert into event_label (event_label_id, color, event_id, name)
values (:'renameLabelID', '#DBEAFE', :'renameEventID', 'Backend');

-- Label stored by an earlier attempt
insert into event_label (event_label_id, color, event_id, name)
values (:'retryLabelID', '#DBEAFE', :'retryEventID', 'Retry');

-- First label in the name rotation
insert into event_label (event_label_id, color, event_id, name)
values (:'rotateLabel1ID', '#DBEAFE', :'rotateEventID', 'One');

-- Second label in the name rotation
insert into event_label (event_label_id, color, event_id, name)
values (:'rotateLabel2ID', '#FEE2E2', :'rotateEventID', 'Two');

-- Third label in the name rotation
insert into event_label (event_label_id, color, event_id, name)
values (:'rotateLabel3ID', '#CCFBF1', :'rotateEventID', 'Three');

-- Label kept when a stale identifier is rejected
insert into event_label (event_label_id, color, event_id, name)
values (:'staleLabelID', '#DBEAFE', :'staleEventID', 'Stale');

-- First label in the name swap
insert into event_label (event_label_id, color, event_id, name)
values (:'swapLeftLabelID', '#DBEAFE', :'swapEventID', 'Left');

-- Second label in the name swap
insert into event_label (event_label_id, color, event_id, name)
values (:'swapRightLabelID', '#FEE2E2', :'swapEventID', 'Right');

-- Submission link to the removed label
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'cascadeSubmissionID', :'cascadeRemoveLabelID');

-- Session linked to the kept and removed labels
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'cascadeSessionID', :'cascadeEventID', 'Cascade Session', 'in-person', '2030-01-01 10:00:00+00');

-- Session link to the kept label
insert into session_label (event_label_id, session_id)
values (:'cascadeKeepLabelID', :'cascadeSessionID');

-- Session link to the removed label
insert into session_label (event_label_id, session_id)
values (:'cascadeRemoveLabelID', :'cascadeSessionID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cascade removed labels to their links
select lives_ok(
    format(
        $$select sync_event_labels(%L::uuid, %L::jsonb)$$,
        :'cascadeEventID',
        jsonb_build_array(
            jsonb_build_object(
                'color', '#DBEAFE',
                'event_label_id', :'cascadeKeepLabelID'::uuid,
                'is_new', false,
                'name', 'Keep'
            )
        )
    ),
    'Should cascade removed labels to their links'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'cascadeEventID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text)$$,
        :'cascadeKeepLabelID', 'Keep', '#DBEAFE'
    ),
    'Should keep only the labels in the payload'
);
select results_eq(
    format($$select event_label_id from session_label where session_id = %L::uuid$$, :'cascadeSessionID'),
    format($$values (%L::uuid)$$, :'cascadeKeepLabelID'),
    'Should unlink removed labels from sessions'
);
select is(
    (select count(*)::int from cfs_submission_label where cfs_submission_id = :'cascadeSubmissionID'),
    0,
    'Should unlink removed labels from submissions'
);

-- Should insert new labels with the supplied identifiers
select lives_ok(
    format(
        $$select sync_event_labels(%L::uuid, %L::jsonb)$$,
        :'insertEventID',
        jsonb_build_array(
            jsonb_build_object(
                'color', '#DBEAFE',
                'event_label_id', :'insertLabelID'::uuid,
                'is_new', true,
                'name', 'Backend'
            )
        )
    ),
    'Should insert new labels with the supplied identifiers'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'insertEventID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text)$$,
        :'insertLabelID', 'Backend', '#DBEAFE'
    ),
    'Should store new labels with the supplied identifiers'
);

-- Should keep label identifiers when renaming and recoloring labels
select lives_ok(
    format(
        $$select sync_event_labels(%L::uuid, %L::jsonb)$$,
        :'renameEventID',
        jsonb_build_array(
            jsonb_build_object(
                'color', '#FEE2E2',
                'event_label_id', :'renameLabelID'::uuid,
                'is_new', false,
                'name', '  Platform  '
            )
        )
    ),
    'Should keep label identifiers when renaming and recoloring labels'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'renameEventID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text)$$,
        :'renameLabelID', 'Platform', '#FEE2E2'
    ),
    'Should store trimmed names and new colors under the same identifiers'
);

-- Should reject a duplicate final label name
select throws_ok(
    format(
        $$select sync_event_labels(%L::uuid, %L::jsonb)$$,
        :'duplicateEventID',
        jsonb_build_array(
            jsonb_build_object(
                'color', '#DBEAFE',
                'event_label_id', :'duplicateLabelAID'::uuid,
                'is_new', false,
                'name', 'Gamma'
            ),
            jsonb_build_object(
                'color', '#FEE2E2',
                'event_label_id', :'duplicateLabelBID'::uuid,
                'is_new', false,
                'name', 'Gamma'
            )
        )
    ),
    'OCG01',
    'duplicate label names',
    'Should reject a duplicate final label name'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'duplicateEventID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text), (%L::uuid, %L::text, %L::text)$$,
        :'duplicateLabelAID', 'Alpha', '#DBEAFE',
        :'duplicateLabelBID', 'Beta', '#FEE2E2'
    ),
    'Should keep labels when rejecting a duplicate final label name'
);

-- Should reject a null labels payload
select throws_ok(
    format($$select sync_event_labels(%L::uuid, null)$$, :'nullEventID'),
    'P0001',
    'labels payload is required',
    'Should reject a null labels payload'
);

-- Should reject a stale existing label identifier
select throws_ok(
    format(
        $$select sync_event_labels(%L::uuid, %L::jsonb)$$,
        :'staleEventID',
        jsonb_build_array(
            jsonb_build_object(
                'color', '#FEE2E2',
                'event_label_id', :'staleLabelID'::uuid,
                'is_new', false,
                'name', 'Renamed'
            ),
            jsonb_build_object(
                'color', '#DBEAFE',
                'event_label_id', :'staleMissingLabelID'::uuid,
                'is_new', false,
                'name', 'Missing'
            )
        )
    ),
    'OCG01',
    'event label not found for event',
    'Should reject a stale existing label identifier'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'staleEventID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text)$$,
        :'staleLabelID', 'Stale', '#DBEAFE'
    ),
    'Should keep labels when rejecting a stale label identifier'
);

-- Should reject label identifiers owned by another event
select throws_ok(
    format(
        $$select sync_event_labels(%L::uuid, %L::jsonb)$$,
        :'foreignEventID',
        jsonb_build_array(
            jsonb_build_object(
                'color', '#CCFBF1',
                'event_label_id', :'foreignOwnerLabelID'::uuid,
                'is_new', true,
                'name', 'Hijacked'
            )
        )
    ),
    'OCG01',
    'event label not found for event',
    'Should reject label identifiers owned by another event'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'foreignEventID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text)$$,
        :'foreignEventLabelID', 'Own', '#DBEAFE'
    ),
    'Should keep the event labels when rejecting a foreign label'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'foreignOwnerEventID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text)$$,
        :'foreignOwnerLabelID', 'Owned', '#FEE2E2'
    ),
    'Should leave the other event label untouched'
);

-- Should remove all labels for an empty payload
select lives_ok(
    format(
        $$select sync_event_labels(%L::uuid, %L::jsonb)$$,
        :'clearEventID',
        '[]'::jsonb
    ),
    'Should remove all labels for an empty payload'
);
select is(
    (select count(*)::int from event_label where event_id = :'clearEventID'),
    0,
    'Should leave no labels after an empty payload'
);

-- Should replace a removed label with a new label of the same name
select lives_ok(
    format(
        $$select sync_event_labels(%L::uuid, %L::jsonb)$$,
        :'recreateEventID',
        jsonb_build_array(
            jsonb_build_object(
                'color', '#FEE2E2',
                'event_label_id', :'recreateNewLabelID'::uuid,
                'is_new', true,
                'name', 'Alpha'
            )
        )
    ),
    'Should replace a removed label with a new label of the same name'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'recreateEventID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text)$$,
        :'recreateNewLabelID', 'Alpha', '#FEE2E2'
    ),
    'Should store only the new label with the reused name'
);

-- Should rotate names across three labels
select lives_ok(
    format(
        $$select sync_event_labels(%L::uuid, %L::jsonb)$$,
        :'rotateEventID',
        jsonb_build_array(
            jsonb_build_object(
                'color', '#DBEAFE',
                'event_label_id', :'rotateLabel1ID'::uuid,
                'is_new', false,
                'name', 'Two'
            ),
            jsonb_build_object(
                'color', '#FEE2E2',
                'event_label_id', :'rotateLabel2ID'::uuid,
                'is_new', false,
                'name', 'Three'
            ),
            jsonb_build_object(
                'color', '#CCFBF1',
                'event_label_id', :'rotateLabel3ID'::uuid,
                'is_new', false,
                'name', 'One'
            )
        )
    ),
    'Should rotate names across three labels'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'rotateEventID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text), (%L::uuid, %L::text, %L::text), (%L::uuid, %L::text, %L::text)$$,
        :'rotateLabel3ID', 'One', '#CCFBF1',
        :'rotateLabel2ID', 'Three', '#FEE2E2',
        :'rotateLabel1ID', 'Two', '#DBEAFE'
    ),
    'Should store the rotated names'
);

-- Should swap two label names
select lives_ok(
    format(
        $$select sync_event_labels(%L::uuid, %L::jsonb)$$,
        :'swapEventID',
        jsonb_build_array(
            jsonb_build_object(
                'color', '#DBEAFE',
                'event_label_id', :'swapLeftLabelID'::uuid,
                'is_new', false,
                'name', 'Right'
            ),
            jsonb_build_object(
                'color', '#FEE2E2',
                'event_label_id', :'swapRightLabelID'::uuid,
                'is_new', false,
                'name', 'Left'
            )
        )
    ),
    'Should swap two label names'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'swapEventID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text), (%L::uuid, %L::text, %L::text)$$,
        :'swapRightLabelID', 'Left', '#FEE2E2',
        :'swapLeftLabelID', 'Right', '#DBEAFE'
    ),
    'Should store the swapped names'
);

-- Should update an existing label when retrying a new label identifier
select lives_ok(
    format(
        $$select sync_event_labels(%L::uuid, %L::jsonb)$$,
        :'retryEventID',
        jsonb_build_array(
            jsonb_build_object(
                'color', '#FEE2E2',
                'event_label_id', :'retryLabelID'::uuid,
                'is_new', true,
                'name', 'Retried'
            )
        )
    ),
    'Should update an existing label when retrying a new label identifier'
);
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'retryEventID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text)$$,
        :'retryLabelID', 'Retried', '#FEE2E2'
    ),
    'Should store the retried label values'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
