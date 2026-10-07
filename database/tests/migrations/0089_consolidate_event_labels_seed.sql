-- Seeds schema-88 CFS label shapes for the event labels consolidation upgrade test.

begin;

\set communityID '89000000-0000-0000-0000-000000000001'
\set eventCategoryID '89000000-0000-0000-0000-000000000002'
\set groupCategoryID '89000000-0000-0000-0000-000000000003'
\set groupID '89000000-0000-0000-0000-000000000004'
\set labelBackendID '89000000-0000-0000-0000-000000000005'
\set labelFrontendID '89000000-0000-0000-0000-000000000006'
\set labelOtherEventID '89000000-0000-0000-0000-000000000007'
\set labeledEventID '89000000-0000-0000-0000-000000000008'
\set labeledLinkedProposalID '89000000-0000-0000-0000-000000000009'
\set labeledLinkedSessionID '89000000-0000-0000-0000-000000000010'
\set labeledLinkedSubmissionID '89000000-0000-0000-0000-000000000011'
\set labeledTicketTypeID '89000000-0000-0000-0000-000000000012'
\set labeledUnlinkedProposalID '89000000-0000-0000-0000-000000000013'
\set labeledUnlinkedSubmissionID '89000000-0000-0000-0000-000000000014'
\set otherEventID '89000000-0000-0000-0000-000000000015'
\set otherProposalID '89000000-0000-0000-0000-000000000016'
\set otherSubmissionID '89000000-0000-0000-0000-000000000017'
\set otherTicketTypeID '89000000-0000-0000-0000-000000000018'
\set unlabeledLinkedProposalID '89000000-0000-0000-0000-000000000019'
\set unlabeledLinkedSessionID '89000000-0000-0000-0000-000000000020'
\set unlabeledLinkedSubmissionID '89000000-0000-0000-0000-000000000021'
\set unlinkedSessionID '89000000-0000-0000-0000-000000000022'
\set userID '89000000-0000-0000-0000-000000000023'

-- Community hosting the migration fixtures
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    'https://example.test/banner-mobile.png',
    'https://example.test/banner.png',
    'Event labels upgrade fixtures',
    'Event Labels Community',
    'https://example.test/logo.png',
    'event-labels-community'
);

-- Event category of the labeled events
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Event labels events');

-- Group category of the fixture group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Event labels groups');

-- Speaker who owns every session proposal
insert into "user" (auth_hash, email, email_verified, user_id, username)
values ('hash', 'event-labels-speaker@example.test', true, :'userID', 'event-labels-speaker');

-- Group owning the labeled events
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Event Labels Group', 'event-labels-group');

-- Proposal submitted with labels and linked to a session
insert into session_proposal (
    description,
    duration,
    session_proposal_id,
    session_proposal_level_id,
    title,
    user_id
) values (
    'Labeled linked description',
    interval '30 minutes',
    :'labeledLinkedProposalID',
    'beginner',
    'Labeled Linked',
    :'userID'
);

-- Proposal submitted with labels and not linked to a session
insert into session_proposal (
    description,
    duration,
    session_proposal_id,
    session_proposal_level_id,
    title,
    user_id
) values (
    'Labeled unlinked description',
    interval '30 minutes',
    :'labeledUnlinkedProposalID',
    'beginner',
    'Labeled Unlinked',
    :'userID'
);

-- Proposal submitted with labels to the other event
insert into session_proposal (
    description,
    duration,
    session_proposal_id,
    session_proposal_level_id,
    title,
    user_id
) values (
    'Other event description',
    interval '30 minutes',
    :'otherProposalID',
    'beginner',
    'Other Event',
    :'userID'
);

-- Proposal submitted without labels and linked to a session
insert into session_proposal (
    description,
    duration,
    session_proposal_id,
    session_proposal_level_id,
    title,
    user_id
) values (
    'Unlabeled linked description',
    interval '30 minutes',
    :'unlabeledLinkedProposalID',
    'beginner',
    'Unlabeled Linked',
    :'userID'
);

-- Event whose labels are shared by submissions and sessions
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone
) values (
    20,
    'Labeled event',
    '2099-01-01 12:00:00+00',
    :'eventCategoryID',
    :'labeledEventID',
    'in-person',
    :'groupID',
    'Labeled Event',
    'labeled-event',
    '2099-01-01 09:00:00+00',
    'UTC'
);

-- Event whose labels must stay on their own event
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone
) values (
    20,
    'Other labeled event',
    '2099-02-01 12:00:00+00',
    :'eventCategoryID',
    :'otherEventID',
    'in-person',
    :'groupID',
    'Other Labeled Event',
    'other-labeled-event',
    '2099-02-01 09:00:00+00',
    'UTC'
);

-- Approved submission with labels linked to a session
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'labeledLinkedSubmissionID', :'labeledEventID', :'labeledLinkedProposalID', 'approved');

-- Submission with labels not linked to any session
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'labeledUnlinkedSubmissionID', :'labeledEventID', :'labeledUnlinkedProposalID', 'not-reviewed');

-- Submission with labels on the other event
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'otherSubmissionID', :'otherEventID', :'otherProposalID', 'not-reviewed');

-- Approved submission without labels linked to a session
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'unlabeledLinkedSubmissionID', :'labeledEventID', :'unlabeledLinkedProposalID', 'approved');

-- Backend label of the labeled event
insert into event_cfs_label (color, created_at, event_cfs_label_id, event_id, name)
values ('#DBEAFE', '2024-01-01 10:00:00+00', :'labelBackendID', :'labeledEventID', 'track / backend');

-- Frontend label of the labeled event
insert into event_cfs_label (color, created_at, event_cfs_label_id, event_id, name)
values ('#FEE2E2', '2024-01-02 10:00:00+00', :'labelFrontendID', :'labeledEventID', 'track / frontend');

-- Label of the other event sharing a name with the labeled event
insert into event_cfs_label (color, created_at, event_cfs_label_id, event_id, name)
values ('#CCFBF1', '2024-01-03 10:00:00+00', :'labelOtherEventID', :'otherEventID', 'track / backend');

-- Ticket tier required by the labeled event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'labeledEventID', :'labeledTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the other event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'otherEventID', :'otherTicketTypeID', 1, 20, 'General admission');

-- Session linked to the labeled submission
insert into session (cfs_submission_id, event_id, name, session_id, session_kind_id, starts_at)
values (
    :'labeledLinkedSubmissionID',
    :'labeledEventID',
    'Labeled Linked Session',
    :'labeledLinkedSessionID',
    'in-person',
    '2099-01-01 10:00:00+00'
);

-- Session linked to the unlabeled submission
insert into session (cfs_submission_id, event_id, name, session_id, session_kind_id, starts_at)
values (
    :'unlabeledLinkedSubmissionID',
    :'labeledEventID',
    'Unlabeled Linked Session',
    :'unlabeledLinkedSessionID',
    'in-person',
    '2099-01-01 11:00:00+00'
);

-- Session not linked to any submission
insert into session (event_id, name, session_id, session_kind_id, starts_at)
values (:'labeledEventID', 'Unlinked Session', :'unlinkedSessionID', 'in-person', '2099-01-01 11:30:00+00');

-- Labels of the submission linked to a session
insert into cfs_submission_label (cfs_submission_id, created_at, event_cfs_label_id)
values
    (:'labeledLinkedSubmissionID', '2024-02-01 10:00:00+00', :'labelBackendID'),
    (:'labeledLinkedSubmissionID', '2024-02-02 10:00:00+00', :'labelFrontendID');

-- Label of the submission not linked to any session
insert into cfs_submission_label (cfs_submission_id, created_at, event_cfs_label_id)
values (:'labeledUnlinkedSubmissionID', '2024-02-03 10:00:00+00', :'labelFrontendID');

-- Label of the submission on the other event
insert into cfs_submission_label (cfs_submission_id, created_at, event_cfs_label_id)
values (:'otherSubmissionID', '2024-02-04 10:00:00+00', :'labelOtherEventID');

commit;
