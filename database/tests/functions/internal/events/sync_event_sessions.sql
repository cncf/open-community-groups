-- Tests synchronizing event sessions, speakers and labels from an update payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(28);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set clearEventID '3a340000-0000-0000-0000-000000000001'
\set clearExistingLabelID '3a340000-0000-0000-0000-000000000002'
\set clearExistingSessionID '3a340000-0000-0000-0000-000000000003'
\set clearLinkedLabelID '3a340000-0000-0000-0000-000000000004'
\set clearLinkedProposalID '3a340000-0000-0000-0000-000000000005'
\set clearLinkedSubmissionID '3a340000-0000-0000-0000-000000000006'
\set communityID '3a340000-0000-0000-0000-000000000007'
\set copyEventID '3a340000-0000-0000-0000-000000000008'
\set copyLabelID '3a340000-0000-0000-0000-000000000009'
\set copyProposalID '3a340000-0000-0000-0000-00000000000a'
\set copySubmissionID '3a340000-0000-0000-0000-00000000000b'
\set crossEventID '3a340000-0000-0000-0000-00000000000c'
\set crossLabelID '3a340000-0000-0000-0000-00000000000d'
\set crossOtherEventID '3a340000-0000-0000-0000-00000000000e'
\set crossOtherLabelID '3a340000-0000-0000-0000-00000000000f'
\set crossSessionID '3a340000-0000-0000-0000-000000000010'
\set eventCategoryID '3a340000-0000-0000-0000-000000000011'
\set eventID '3a340000-0000-0000-0000-000000000012'
\set groupCategoryID '3a340000-0000-0000-0000-000000000013'
\set groupID '3a340000-0000-0000-0000-000000000014'
\set keepLinkedEventID '3a340000-0000-0000-0000-000000000015'
\set keepLinkedProposalID '3a340000-0000-0000-0000-000000000016'
\set keepLinkedSessionID '3a340000-0000-0000-0000-000000000017'
\set keepLinkedSessionLabelID '3a340000-0000-0000-0000-000000000018'
\set keepLinkedSubmissionID '3a340000-0000-0000-0000-000000000019'
\set keepLinkedSubmissionLabelID '3a340000-0000-0000-0000-00000000001a'
\set laterCopiedLabelID '3a340000-0000-0000-0000-00000000001b'
\set laterEventID '3a340000-0000-0000-0000-00000000001c'
\set laterNewLabelID '3a340000-0000-0000-0000-00000000001d'
\set laterProposalID '3a340000-0000-0000-0000-00000000001e'
\set laterSessionID '3a340000-0000-0000-0000-00000000001f'
\set laterSubmissionID '3a340000-0000-0000-0000-000000000020'
\set missingSessionID '3a340000-0000-0000-0000-000000000021'
\set relinkEventID '3a340000-0000-0000-0000-000000000022'
\set relinkNewLabelID '3a340000-0000-0000-0000-000000000023'
\set relinkNewProposalID '3a340000-0000-0000-0000-000000000024'
\set relinkNewSubmissionID '3a340000-0000-0000-0000-000000000025'
\set relinkOldLabelID '3a340000-0000-0000-0000-000000000026'
\set relinkOldProposalID '3a340000-0000-0000-0000-000000000027'
\set relinkOldSubmissionID '3a340000-0000-0000-0000-000000000028'
\set relinkSessionID '3a340000-0000-0000-0000-000000000029'
\set replaceEventID '3a340000-0000-0000-0000-00000000002a'
\set replaceNewLabelID '3a340000-0000-0000-0000-00000000002b'
\set replaceOldLabelID '3a340000-0000-0000-0000-00000000002c'
\set replaceSessionID '3a340000-0000-0000-0000-00000000002d'
\set session1ID '3a340000-0000-0000-0000-00000000002e'
\set session2ID '3a340000-0000-0000-0000-00000000002f'
\set unlinkedEventID '3a340000-0000-0000-0000-000000000030'
\set unlinkedFormerProposalID '3a340000-0000-0000-0000-000000000031'
\set unlinkedFormerSessionID '3a340000-0000-0000-0000-000000000032'
\set unlinkedFormerSubmissionID '3a340000-0000-0000-0000-000000000033'
\set unlinkedFormerSubmissionLabelID '3a340000-0000-0000-0000-000000000034'
\set unlinkedLabelID '3a340000-0000-0000-0000-000000000035'
\set unlinkedSessionID '3a340000-0000-0000-0000-000000000036'
\set user1ID '3a340000-0000-0000-0000-000000000037'
\set user2ID '3a340000-0000-0000-0000-000000000038'
\set user3ID '3a340000-0000-0000-0000-000000000039'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the events with sessions
select fx_community(:'communityID');

-- Speaker of the opening session and owner of the CFS proposals
select fx_user(:'user1ID', jsonb_build_object('username', 'user1-sync-event-sessions'));

-- Speaker of the obsolete session
select fx_user(:'user2ID', jsonb_build_object('username', 'user2-sync-event-sessions'));

-- Speaker replacing the opening session speaker
select fx_user(:'user3ID', jsonb_build_object('username', 'user3-sync-event-sessions'));

-- Event category used by the events with sessions
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Proposal linked to a new session with empty label IDs
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'clearLinkedProposalID',
    'Clear Linked description',
    interval '30 minutes',
    'beginner',
    'Clear Linked',
    :'user1ID'
);

-- Proposal linked to a new session that copies its labels
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'copyProposalID',
    'Copy description',
    interval '30 minutes',
    'beginner',
    'Copy',
    :'user1ID'
);

-- Proposal linked to an unchanged session
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'keepLinkedProposalID',
    'Keep Linked description',
    interval '30 minutes',
    'beginner',
    'Keep Linked',
    :'user1ID'
);

-- Proposal whose labels change after linking
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'laterProposalID',
    'Later description',
    interval '30 minutes',
    'beginner',
    'Later',
    :'user1ID'
);

-- Proposal newly linked to a session
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'relinkNewProposalID',
    'Relink New description',
    interval '30 minutes',
    'beginner',
    'Relink New',
    :'user1ID'
);

-- Proposal previously linked to a session
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'relinkOldProposalID',
    'Relink Old description',
    interval '30 minutes',
    'beginner',
    'Relink Old',
    :'user1ID'
);

-- Proposal unlinked from its session
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'unlinkedFormerProposalID',
    'Unlinked Former description',
    interval '30 minutes',
    'beginner',
    'Unlinked Former',
    :'user1ID'
);

-- Group hosting the events with sessions
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event clearing session labels with empty label IDs
select fx_event(:'clearEventID', :'groupID', :'eventCategoryID');

-- Event adding a session linked to a labeled submission
select fx_event(:'copyEventID', :'groupID', :'eventCategoryID');

-- Event receiving a session label from another event
select fx_event(:'crossEventID', :'groupID', :'eventCategoryID');

-- Event owning the label rejected for another event
select fx_event(:'crossOtherEventID', :'groupID', :'eventCategoryID');

-- Event whose sessions and speakers are synchronized
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-01-01 17:00:00+00',
    'event_kind_id', 'virtual',
    'starts_at', '2030-01-01 09:00:00+00'
));

-- Event keeping the labels of an unchanged linked session
select fx_event(:'keepLinkedEventID', :'groupID', :'eventCategoryID');

-- Event whose submission labels change after linking
select fx_event(:'laterEventID', :'groupID', :'eventCategoryID');

-- Event linking a session to another submission
select fx_event(:'relinkEventID', :'groupID', :'eventCategoryID');

-- Event replacing session labels with submitted label IDs
select fx_event(:'replaceEventID', :'groupID', :'eventCategoryID');

-- Event keeping the labels of unlinked sessions
select fx_event(:'unlinkedEventID', :'groupID', :'eventCategoryID');

-- Approved submission linked to a new session with empty label IDs
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'clearLinkedSubmissionID', :'clearEventID', :'clearLinkedProposalID', 'approved');

-- Approved submission whose labels are copied to a new session
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'copySubmissionID', :'copyEventID', :'copyProposalID', 'approved');

-- Approved submission linked to an unchanged session
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'keepLinkedSubmissionID', :'keepLinkedEventID', :'keepLinkedProposalID', 'approved');

-- Approved submission whose labels change after linking
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'laterSubmissionID', :'laterEventID', :'laterProposalID', 'approved');

-- Approved submission newly linked to a session
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'relinkNewSubmissionID', :'relinkEventID', :'relinkNewProposalID', 'approved');

-- Approved submission previously linked to a session
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'relinkOldSubmissionID', :'relinkEventID', :'relinkOldProposalID', 'approved');

-- Approved submission unlinked from its session
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'unlinkedFormerSubmissionID', :'unlinkedEventID', :'unlinkedFormerProposalID', 'approved');

-- Label cleared from an existing session
insert into event_label (event_label_id, color, event_id, name)
values (:'clearExistingLabelID', '#DBEAFE', :'clearEventID', 'Clear Existing');

-- Label of the submission linked with empty label IDs
insert into event_label (event_label_id, color, event_id, name)
values (:'clearLinkedLabelID', '#FEE2E2', :'clearEventID', 'Clear Linked');

-- Label copied from the linked submission
insert into event_label (event_label_id, color, event_id, name)
values (:'copyLabelID', '#DBEAFE', :'copyEventID', 'Copy');

-- Label kept when a foreign label is rejected
insert into event_label (event_label_id, color, event_id, name)
values (:'crossLabelID', '#DBEAFE', :'crossEventID', 'Cross');

-- Label owned by another event
insert into event_label (event_label_id, color, event_id, name)
values (:'crossOtherLabelID', '#FEE2E2', :'crossOtherEventID', 'Cross Other');

-- Label chosen for the unchanged linked session
insert into event_label (event_label_id, color, event_id, name)
values (:'keepLinkedSessionLabelID', '#DBEAFE', :'keepLinkedEventID', 'Keep Session');

-- Label of the submission linked to the unchanged session
insert into event_label (event_label_id, color, event_id, name)
values (:'keepLinkedSubmissionLabelID', '#FEE2E2', :'keepLinkedEventID', 'Keep Submission');

-- Label copied before the submission labels change
insert into event_label (event_label_id, color, event_id, name)
values (:'laterCopiedLabelID', '#DBEAFE', :'laterEventID', 'Later Copied');

-- Label assigned to the submission after linking
insert into event_label (event_label_id, color, event_id, name)
values (:'laterNewLabelID', '#FEE2E2', :'laterEventID', 'Later New');

-- Label of the newly linked submission
insert into event_label (event_label_id, color, event_id, name)
values (:'relinkNewLabelID', '#FEE2E2', :'relinkEventID', 'Relink New');

-- Label of the previously linked submission
insert into event_label (event_label_id, color, event_id, name)
values (:'relinkOldLabelID', '#DBEAFE', :'relinkEventID', 'Relink Old');

-- Label submitted for the session
insert into event_label (event_label_id, color, event_id, name)
values (:'replaceNewLabelID', '#FEE2E2', :'replaceEventID', 'Replace New');

-- Label replaced on the session
insert into event_label (event_label_id, color, event_id, name)
values (:'replaceOldLabelID', '#DBEAFE', :'replaceEventID', 'Replace Old');

-- Label of the submission unlinked from its session
insert into event_label (event_label_id, color, event_id, name)
values (:'unlinkedFormerSubmissionLabelID', '#FEE2E2', :'unlinkedEventID', 'Unlinked Submission');

-- Label kept by the unlinked sessions
insert into event_label (event_label_id, color, event_id, name)
values (:'unlinkedLabelID', '#DBEAFE', :'unlinkedEventID', 'Unlinked');

-- Label of the submission linked with empty label IDs
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'clearLinkedSubmissionID', :'clearLinkedLabelID');

-- Label of the submission copied to a new session
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'copySubmissionID', :'copyLabelID');

-- Label of the submission linked to the unchanged session
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'keepLinkedSubmissionID', :'keepLinkedSubmissionLabelID');

-- Label of the submission before it changes
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'laterSubmissionID', :'laterCopiedLabelID');

-- Label of the newly linked submission
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'relinkNewSubmissionID', :'relinkNewLabelID');

-- Label of the previously linked submission
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'relinkOldSubmissionID', :'relinkOldLabelID');

-- Label of the submission unlinked from its session
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'unlinkedFormerSubmissionID', :'unlinkedFormerSubmissionLabelID');

-- Session whose labels are cleared
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'clearExistingSessionID', :'clearEventID', 'Clear Existing', 'in-person', '2030-01-01 10:00:00+00');

-- Session receiving a label from another event
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'crossSessionID', :'crossEventID', 'Cross', 'in-person', '2030-01-01 10:00:00+00');

-- Session linked to a submission without changes
insert into session (session_id, cfs_submission_id, event_id, name, session_kind_id, starts_at)
values (:'keepLinkedSessionID', :'keepLinkedSubmissionID', :'keepLinkedEventID', 'Keep Linked', 'in-person', '2030-01-01 10:00:00+00');

-- Session linked to a submission whose labels change later
insert into session (session_id, cfs_submission_id, event_id, name, session_kind_id, starts_at)
values (:'laterSessionID', :'laterSubmissionID', :'laterEventID', 'Later', 'in-person', '2030-01-01 10:00:00+00');

-- Session linked to another submission by the payload
insert into session (session_id, cfs_submission_id, event_id, name, session_kind_id, starts_at)
values (:'relinkSessionID', :'relinkOldSubmissionID', :'relinkEventID', 'Relink', 'in-person', '2030-01-01 10:00:00+00');

-- Session whose labels are replaced
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'replaceSessionID', :'replaceEventID', 'Replace', 'in-person', '2030-01-01 10:00:00+00');

-- Opening session updated by the payload
insert into session (session_id, event_id, name, session_kind_id, starts_at, ends_at)
values (:'session1ID', :'eventID', 'Opening Session', 'virtual', '2030-01-01 10:00:00+00', '2030-01-01 11:00:00+00');

-- Obsolete session removed by the payload
insert into session (session_id, event_id, name, session_kind_id, starts_at, ends_at)
values (:'session2ID', :'eventID', 'Obsolete Session', 'in-person', '2030-01-01 11:30:00+00', '2030-01-01 12:00:00+00');

-- Session unlinked from its submission by the payload
insert into session (session_id, cfs_submission_id, event_id, name, session_kind_id, starts_at)
values (:'unlinkedFormerSessionID', :'unlinkedFormerSubmissionID', :'unlinkedEventID', 'Unlinked Former', 'in-person', '2030-01-01 10:00:00+00');

-- Session never linked to a submission
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'unlinkedSessionID', :'unlinkedEventID', 'Unlinked', 'in-person', '2030-01-01 11:00:00+00');

-- Label cleared from the existing session
insert into session_label (event_label_id, session_id)
values (:'clearExistingLabelID', :'clearExistingSessionID');

-- Label kept when a foreign label is rejected
insert into session_label (event_label_id, session_id)
values (:'crossLabelID', :'crossSessionID');

-- Label chosen for the unchanged linked session
insert into session_label (event_label_id, session_id)
values (:'keepLinkedSessionLabelID', :'keepLinkedSessionID');

-- Label copied from the submission before it changes
insert into session_label (event_label_id, session_id)
values (:'laterCopiedLabelID', :'laterSessionID');

-- Label copied from the previously linked submission
insert into session_label (event_label_id, session_id)
values (:'relinkOldLabelID', :'relinkSessionID');

-- Label replaced on the session
insert into session_label (event_label_id, session_id)
values (:'replaceOldLabelID', :'replaceSessionID');

-- Label kept by the session unlinked from its submission
insert into session_label (event_label_id, session_id)
values (:'unlinkedLabelID', :'unlinkedFormerSessionID');

-- Label kept by the session never linked
insert into session_label (event_label_id, session_id)
values (:'unlinkedLabelID', :'unlinkedSessionID');

-- Opening session speaker replaced by the payload
insert into session_speaker (session_id, user_id, featured)
values (:'session1ID', :'user1ID', false);

-- Obsolete session speaker removed with its session
insert into session_speaker (session_id, user_id, featured)
values (:'session2ID', :'user2ID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should clear session labels for empty submitted label IDs
select lives_ok(
    format(
        $$select sync_event_sessions(
            %L::uuid,
            %L::jsonb,
            (select e from event e where e.event_id = %L::uuid)
        )$$,
        :'clearEventID',
        jsonb_build_object(
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'kind', 'in-person',
                    'label_ids', '[]'::jsonb,
                    'name', 'Clear Existing',
                    'session_id', :'clearExistingSessionID'::uuid,
                    'starts_at', '2030-01-01T10:00:00'
                ),
                jsonb_build_object(
                    'cfs_submission_id', :'clearLinkedSubmissionID'::uuid,
                    'kind', 'in-person',
                    'label_ids', '[]'::jsonb,
                    'name', 'Clear Linked',
                    'starts_at', '2030-01-01T11:00:00'
                )
            ),
            'timezone', 'UTC'
        ),
        :'clearEventID'
    ),
    'Should clear session labels for empty submitted label IDs'
);
select is(
    (select count(*)::int from session_label where session_id = :'clearExistingSessionID'),
    0,
    'Should remove the labels of existing sessions for empty label IDs'
);
select is(
    (
        select count(*)::int
        from session_label sl
        join session s on s.session_id = sl.session_id
        where s.cfs_submission_id = :'clearLinkedSubmissionID'
    ),
    0,
    'Should not copy submission labels when empty label IDs are submitted'
);

-- Should copy submission labels to new linked sessions
select lives_ok(
    format(
        $$select sync_event_sessions(
            %L::uuid,
            %L::jsonb,
            (select e from event e where e.event_id = %L::uuid)
        )$$,
        :'copyEventID',
        jsonb_build_object(
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'cfs_submission_id', :'copySubmissionID'::uuid,
                    'kind', 'in-person',
                    'name', 'Copy',
                    'starts_at', '2030-01-01T10:00:00'
                )
            ),
            'timezone', 'UTC'
        ),
        :'copyEventID'
    ),
    'Should copy submission labels to new linked sessions'
);
select results_eq(
    format(
        $$
            select sl.event_label_id
            from session_label sl
            join session s on s.session_id = sl.session_id
            where s.cfs_submission_id = %L::uuid
        $$,
        :'copySubmissionID'
    ),
    format($$values (%L::uuid)$$, :'copyLabelID'),
    'Should link new sessions to the labels of their submission'
);

-- Should keep copied labels when submission labels change later
select lives_ok(
    format(
        $$select sync_cfs_submission_labels(%L::uuid, %L::uuid, array[%L::uuid])$$,
        :'laterSubmissionID',
        :'laterEventID',
        :'laterNewLabelID'
    ),
    'Should change the labels of a linked submission'
);
select lives_ok(
    format(
        $$select sync_event_sessions(
            %L::uuid,
            %L::jsonb,
            (select e from event e where e.event_id = %L::uuid)
        )$$,
        :'laterEventID',
        jsonb_build_object(
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'cfs_submission_id', :'laterSubmissionID'::uuid,
                    'kind', 'in-person',
                    'name', 'Later',
                    'session_id', :'laterSessionID'::uuid,
                    'starts_at', '2030-01-01T10:00:00'
                )
            ),
            'timezone', 'UTC'
        ),
        :'laterEventID'
    ),
    'Should keep copied labels when submission labels change later'
);
select results_eq(
    format(
        $$select event_label_id from session_label where session_id = %L::uuid order by event_label_id$$,
        :'laterSessionID'
    ),
    format($$values (%L::uuid)$$, :'laterCopiedLabelID'),
    'Should keep the labels copied before the submission changed'
);

-- Should keep labels of unchanged linked sessions
select lives_ok(
    format(
        $$select sync_event_sessions(
            %L::uuid,
            %L::jsonb,
            (select e from event e where e.event_id = %L::uuid)
        )$$,
        :'keepLinkedEventID',
        jsonb_build_object(
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'cfs_submission_id', :'keepLinkedSubmissionID'::uuid,
                    'kind', 'in-person',
                    'name', 'Keep Linked',
                    'session_id', :'keepLinkedSessionID'::uuid,
                    'starts_at', '2030-01-01T10:00:00'
                )
            ),
            'timezone', 'UTC'
        ),
        :'keepLinkedEventID'
    ),
    'Should keep labels of unchanged linked sessions'
);
select results_eq(
    format(
        $$select event_label_id from session_label where session_id = %L::uuid order by event_label_id$$,
        :'keepLinkedSessionID'
    ),
    format($$values (%L::uuid)$$, :'keepLinkedSessionLabelID'),
    'Should not copy submission labels to unchanged linked sessions'
);

-- Should keep labels of unlinked sessions
select lives_ok(
    format(
        $$select sync_event_sessions(
            %L::uuid,
            %L::jsonb,
            (select e from event e where e.event_id = %L::uuid)
        )$$,
        :'unlinkedEventID',
        jsonb_build_object(
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'kind', 'in-person',
                    'name', 'Unlinked Former',
                    'session_id', :'unlinkedFormerSessionID'::uuid,
                    'starts_at', '2030-01-01T10:00:00'
                ),
                jsonb_build_object(
                    'kind', 'in-person',
                    'name', 'Unlinked',
                    'session_id', :'unlinkedSessionID'::uuid,
                    'starts_at', '2030-01-01T11:00:00'
                )
            ),
            'timezone', 'UTC'
        ),
        :'unlinkedEventID'
    ),
    'Should keep labels of unlinked sessions'
);
select results_eq(
    format(
        $$select event_label_id from session_label where session_id = %L::uuid order by event_label_id$$,
        :'unlinkedFormerSessionID'
    ),
    format($$values (%L::uuid)$$, :'unlinkedLabelID'),
    'Should keep the labels of sessions unlinked from their submission'
);
select results_eq(
    format(
        $$select event_label_id from session_label where session_id = %L::uuid order by event_label_id$$,
        :'unlinkedSessionID'
    ),
    format($$values (%L::uuid)$$, :'unlinkedLabelID'),
    'Should keep the labels of sessions never linked'
);

-- Should reject session label IDs from another event
select throws_ok(
    format(
        $$select sync_event_sessions(
            %L::uuid,
            %L::jsonb,
            (select e from event e where e.event_id = %L::uuid)
        )$$,
        :'crossEventID',
        jsonb_build_object(
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'kind', 'in-person',
                    'label_ids', jsonb_build_array(:'crossOtherLabelID'::uuid),
                    'name', 'Cross',
                    'session_id', :'crossSessionID'::uuid,
                    'starts_at', '2030-01-01T10:00:00'
                )
            ),
            'timezone', 'UTC'
        ),
        :'crossEventID'
    ),
    'OCG01',
    'invalid event labels',
    'Should reject session label IDs from another event'
);
select results_eq(
    format(
        $$select event_label_id from session_label where session_id = %L::uuid order by event_label_id$$,
        :'crossSessionID'
    ),
    format($$values (%L::uuid)$$, :'crossLabelID'),
    'Should keep session labels when rejecting labels from another event'
);

-- Should replace labels of re-linked sessions with the new submission labels
select lives_ok(
    format(
        $$select sync_event_sessions(
            %L::uuid,
            %L::jsonb,
            (select e from event e where e.event_id = %L::uuid)
        )$$,
        :'relinkEventID',
        jsonb_build_object(
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'cfs_submission_id', :'relinkNewSubmissionID'::uuid,
                    'kind', 'in-person',
                    'name', 'Relink',
                    'session_id', :'relinkSessionID'::uuid,
                    'starts_at', '2030-01-01T10:00:00'
                )
            ),
            'timezone', 'UTC'
        ),
        :'relinkEventID'
    ),
    'Should replace labels of re-linked sessions with the new submission labels'
);
select results_eq(
    format(
        $$select event_label_id from session_label where session_id = %L::uuid order by event_label_id$$,
        :'relinkSessionID'
    ),
    format($$values (%L::uuid)$$, :'relinkNewLabelID'),
    'Should link re-linked sessions to the new submission labels'
);

-- Should replace session labels with submitted label IDs
select lives_ok(
    format(
        $$select sync_event_sessions(
            %L::uuid,
            %L::jsonb,
            (select e from event e where e.event_id = %L::uuid)
        )$$,
        :'replaceEventID',
        jsonb_build_object(
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'kind', 'in-person',
                    'label_ids', jsonb_build_array(:'replaceNewLabelID'::uuid, :'replaceNewLabelID'::uuid),
                    'name', 'Replace',
                    'session_id', :'replaceSessionID'::uuid,
                    'starts_at', '2030-01-01T10:00:00'
                )
            ),
            'timezone', 'UTC'
        ),
        :'replaceEventID'
    ),
    'Should replace session labels with submitted label IDs'
);
select results_eq(
    format(
        $$select event_label_id from session_label where session_id = %L::uuid order by event_label_id$$,
        :'replaceSessionID'
    ),
    format($$values (%L::uuid)$$, :'replaceNewLabelID'),
    'Should link sessions to the submitted labels once'
);

-- Should update existing sessions, insert new ones, and remove omitted ones
select lives_ok(
    format(
        $$select sync_event_sessions(
            '%s'::uuid,
            jsonb_build_object(
                'timezone', 'UTC',
                'sessions', jsonb_build_array(
                    jsonb_build_object(
                        'ends_at', '2030-01-01T11:30:00',
                        'name', 'Opening Session Updated',
                        'session_id', '%s',
                        'speakers', jsonb_build_array(
                            jsonb_build_object(
                                'featured', true,
                                'user_id', '%s'
                            )
                        ),
                        'starts_at', '2030-01-01T10:30:00',
                        'kind', 'virtual'
                    ),
                    jsonb_build_object(
                        'ends_at', '2030-01-01T13:00:00',
                        'name', 'New Session',
                        'speakers', jsonb_build_array(
                            jsonb_build_object(
                                'featured', false,
                                'user_id', '%s'
                            )
                        ),
                        'starts_at', '2030-01-01T12:00:00',
                        'kind', 'in-person'
                    )
                )
            ),
            (select e from event e where e.event_id = '%s'::uuid)
        )$$,
        :'eventID',
        :'session1ID',
        :'user3ID',
        :'user2ID',
        :'eventID'
    ),
    'Should update existing sessions, insert new ones, and remove omitted ones'
);

-- Should update existing session fields
select is(
    (
        select jsonb_build_object(
            'ends_at', ends_at,
            'name', name,
            'starts_at', starts_at
        )
        from session
        where session_id = :'session1ID'::uuid
    ),
    jsonb_build_object(
        'ends_at', '2030-01-01 11:30:00+00'::timestamptz,
        'name', 'Opening Session Updated',
        'starts_at', '2030-01-01 10:30:00+00'::timestamptz
    ),
    'Should update existing session fields'
);

-- Should replace speakers for updated sessions
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'featured', featured,
                'user_id', user_id
            )
            order by user_id
        )
        from session_speaker
        where session_id = :'session1ID'::uuid
    ),
    jsonb_build_array(
        jsonb_build_object(
            'featured', true,
            'user_id', :'user3ID'::uuid
        )
    ),
    'Should replace speakers for updated sessions'
);

-- Should insert new sessions from the payload
select is(
    (select count(*) from session where event_id = :'eventID'::uuid and name = 'New Session'),
    1::bigint,
    'Should insert new sessions from the payload'
);

-- Should remove sessions omitted from the payload
select is(
    (select count(*) from session where session_id = :'session2ID'::uuid),
    0::bigint,
    'Should remove sessions omitted from the payload'
);

-- Should leave exactly two sessions after sync
select is(
    (select count(*) from session where event_id = :'eventID'::uuid),
    2::bigint,
    'Should leave exactly two sessions after sync'
);

-- Should delete all sessions when the payload omits them
select lives_ok(
    format(
        $$select sync_event_sessions(
            '%s'::uuid,
            '{"timezone": "UTC"}'::jsonb,
            (select e from event e where e.event_id = '%s'::uuid)
        )$$,
        :'eventID',
        :'eventID'
    ),
    'Should delete all sessions when the payload omits them'
);

-- Should leave no sessions after deleting with an omitted payload
select is(
    (select count(*) from session where event_id = :'eventID'::uuid),
    0::bigint,
    'Should leave no sessions after deleting with an omitted payload'
);

-- Should reject updating a session that does not belong to the event
select throws_ok(
    format(
        $$select sync_event_sessions(
            '%s'::uuid,
            jsonb_build_object(
                'timezone', 'UTC',
                'sessions', jsonb_build_array(
                    jsonb_build_object(
                        'ends_at', '2030-01-01T11:00:00',
                        'name', 'Missing Session',
                        'session_id', '%s',
                        'starts_at', '2030-01-01T10:00:00',
                        'kind', 'virtual'
                    )
                )
            ),
            (select e from event e where e.event_id = '%s'::uuid)
        )$$,
        :'eventID',
        :'missingSessionID',
        :'eventID'
    ),
    format('session %s not found for event %s', :'missingSessionID', :'eventID'),
    'Should reject updating a session that does not belong to the event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
