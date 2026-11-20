-- Tests resolving session speakers from assignments and linked CFS proposals.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set assignedFeaturedUserID '5e55e000-0000-0000-0000-000000000001'
\set assignedSessionID '5e55e000-0000-0000-0000-000000000002'
\set assignedUserID '5e55e000-0000-0000-0000-000000000003'
\set communityID '5e55e000-0000-0000-0000-000000000004'
\set emptySessionID '5e55e000-0000-0000-0000-000000000005'
\set eventCategoryID '5e55e000-0000-0000-0000-000000000006'
\set eventID '5e55e000-0000-0000-0000-000000000007'
\set groupCategoryID '5e55e000-0000-0000-0000-000000000008'
\set groupID '5e55e000-0000-0000-0000-000000000009'
\set linkedAuthorUserID '5e55e000-0000-0000-0000-00000000000a'
\set linkedCoSpeakerUserID '5e55e000-0000-0000-0000-00000000000b'
\set linkedProposalID '5e55e000-0000-0000-0000-00000000000c'
\set linkedSessionID '5e55e000-0000-0000-0000-00000000000d'
\set linkedSubmissionID '5e55e000-0000-0000-0000-00000000000e'
\set overriddenAuthorUserID '5e55e000-0000-0000-0000-00000000000f'
\set overriddenCoSpeakerUserID '5e55e000-0000-0000-0000-000000000010'
\set overriddenProposalID '5e55e000-0000-0000-0000-000000000011'
\set overriddenSessionID '5e55e000-0000-0000-0000-000000000012'
\set overriddenSubmissionID '5e55e000-0000-0000-0000-000000000013'
\set soloAuthorUserID '5e55e000-0000-0000-0000-000000000014'
\set soloProposalID '5e55e000-0000-0000-0000-000000000015'
\set soloSessionID '5e55e000-0000-0000-0000-000000000016'
\set soloSubmissionID '5e55e000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the event with sessions
select fx_community(:'communityID');

-- Featured speaker assigned to the unlinked session
select fx_user(:'assignedFeaturedUserID');

-- Speaker assigned to the unlinked session and to the overridden linked session
select fx_user(:'assignedUserID');

-- Author of the proposal linked with a co-speaker
select fx_user(:'linkedAuthorUserID');

-- Co-speaker of the linked proposal
select fx_user(:'linkedCoSpeakerUserID');

-- Author of the proposal whose session has assigned speakers
select fx_user(:'overriddenAuthorUserID');

-- Co-speaker of the proposal whose session has assigned speakers
select fx_user(:'overriddenCoSpeakerUserID');

-- Author of the proposal linked without a co-speaker
select fx_user(:'soloAuthorUserID');

-- Event category used by the event with sessions
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the event group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Proposal with an author and a co-speaker
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id,
    co_speaker_user_id
) values (
    :'linkedProposalID',
    'Linked description',
    interval '30 minutes',
    'beginner',
    'Linked',
    :'linkedAuthorUserID',
    :'linkedCoSpeakerUserID'
);

-- Proposal whose session speakers are assigned explicitly
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id,
    co_speaker_user_id
) values (
    :'overriddenProposalID',
    'Overridden description',
    interval '30 minutes',
    'beginner',
    'Overridden',
    :'overriddenAuthorUserID',
    :'overriddenCoSpeakerUserID'
);

-- Proposal with an author and no co-speaker
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'soloProposalID',
    'Solo description',
    interval '30 minutes',
    'beginner',
    'Solo',
    :'soloAuthorUserID'
);

-- Group hosting the event with sessions
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose sessions are resolved
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Approved submission of the proposal with a co-speaker
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'linkedSubmissionID', :'eventID', :'linkedProposalID', 'approved');

-- Approved submission of the proposal whose session has assigned speakers
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'overriddenSubmissionID', :'eventID', :'overriddenProposalID', 'approved');

-- Approved submission of the proposal without a co-speaker
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'soloSubmissionID', :'eventID', :'soloProposalID', 'approved');

-- Unlinked session with assigned speakers
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'assignedSessionID', :'eventID', 'Assigned', 'in-person', '2030-01-01 10:00:00+00');

-- Unlinked session without speakers
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'emptySessionID', :'eventID', 'Empty', 'in-person', '2030-01-01 11:00:00+00');

-- Session linked to the proposal with a co-speaker
insert into session (session_id, cfs_submission_id, event_id, name, session_kind_id, starts_at)
values (:'linkedSessionID', :'linkedSubmissionID', :'eventID', 'Linked', 'in-person', '2030-01-01 12:00:00+00');

-- Linked session that also has assigned speakers
insert into session (session_id, cfs_submission_id, event_id, name, session_kind_id, starts_at)
values (:'overriddenSessionID', :'overriddenSubmissionID', :'eventID', 'Overridden', 'in-person', '2030-01-01 13:00:00+00');

-- Session linked to the proposal without a co-speaker
insert into session (session_id, cfs_submission_id, event_id, name, session_kind_id, starts_at)
values (:'soloSessionID', :'soloSubmissionID', :'eventID', 'Solo', 'in-person', '2030-01-01 14:00:00+00');

-- Featured speaker of the unlinked session
insert into session_speaker (session_id, user_id, featured)
values (:'assignedSessionID', :'assignedFeaturedUserID', true);

-- Regular speaker of the unlinked session
insert into session_speaker (session_id, user_id, featured)
values (:'assignedSessionID', :'assignedUserID', false);

-- Speaker assigned to the linked session in place of the proposal speakers
insert into session_speaker (session_id, user_id, featured)
values (:'overriddenSessionID', :'assignedUserID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should find the sessions a user speaks at
select results_eq(
    format(
        $$
            select session_id, user_id
            from session_speakers()
            where user_id in (%L::uuid, %L::uuid)
            order by user_id, session_id
        $$,
        :'assignedUserID',
        :'linkedCoSpeakerUserID'
    ),
    format(
        $$values (%L::uuid, %L::uuid), (%L::uuid, %L::uuid), (%L::uuid, %L::uuid)$$,
        :'assignedSessionID', :'assignedUserID',
        :'overriddenSessionID', :'assignedUserID',
        :'linkedSessionID', :'linkedCoSpeakerUserID'
    ),
    'Should find the sessions a user speaks at'
);

-- Should list the linked proposal author before the co-speaker
select results_eq(
    format(
        $$
            select event_id, featured, session_id, sort_order, user_id
            from session_speakers()
            where session_id = %L::uuid
            order by sort_order
        $$,
        :'linkedSessionID'
    ),
    format(
        $$values (%L::uuid, false, %L::uuid, 0, %L::uuid), (%L::uuid, false, %L::uuid, 1, %L::uuid)$$,
        :'eventID', :'linkedSessionID', :'linkedAuthorUserID',
        :'eventID', :'linkedSessionID', :'linkedCoSpeakerUserID'
    ),
    'Should list the linked proposal author before the co-speaker'
);

-- Should prefer assigned speakers over the linked proposal speakers
select results_eq(
    format(
        $$
            select event_id, featured, session_id, sort_order, user_id
            from session_speakers()
            where session_id = %L::uuid
        $$,
        :'overriddenSessionID'
    ),
    format(
        $$values (%L::uuid, false, %L::uuid, 0, %L::uuid)$$,
        :'eventID', :'overriddenSessionID', :'assignedUserID'
    ),
    'Should prefer assigned speakers over the linked proposal speakers'
);

-- Should return no speakers for unlinked sessions without assigned speakers
select is_empty(
    format(
        $$select user_id from session_speakers() where session_id = %L::uuid$$,
        :'emptySessionID'
    ),
    'Should return no speakers for unlinked sessions without assigned speakers'
);

-- Should return only the author of a linked proposal without a co-speaker
select results_eq(
    format(
        $$
            select event_id, featured, session_id, sort_order, user_id
            from session_speakers()
            where session_id = %L::uuid
        $$,
        :'soloSessionID'
    ),
    format(
        $$values (%L::uuid, false, %L::uuid, 0, %L::uuid)$$,
        :'eventID', :'soloSessionID', :'soloAuthorUserID'
    ),
    'Should return only the author of a linked proposal without a co-speaker'
);

-- Should return the assigned speakers of unlinked sessions
select results_eq(
    format(
        $$
            select event_id, featured, session_id, sort_order, user_id
            from session_speakers()
            where session_id = %L::uuid
            order by featured desc
        $$,
        :'assignedSessionID'
    ),
    format(
        $$values (%L::uuid, true, %L::uuid, 0, %L::uuid), (%L::uuid, false, %L::uuid, 0, %L::uuid)$$,
        :'eventID', :'assignedSessionID', :'assignedFeaturedUserID',
        :'eventID', :'assignedSessionID', :'assignedUserID'
    ),
    'Should return the assigned speakers of unlinked sessions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
