-- Tests resolving audit log resource display names.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cfsSubmissionID '1b010000-0000-0000-0000-000000000001'
\set communityID '1b010000-0000-0000-0000-000000000002'
\set eventCategoryID '1b010000-0000-0000-0000-000000000003'
\set eventID '1b010000-0000-0000-0000-000000000004'
\set groupCategoryID '1b010000-0000-0000-0000-000000000005'
\set groupID '1b010000-0000-0000-0000-000000000006'
\set groupSponsorID '1b010000-0000-0000-0000-000000000007'
\set inboxConversationID '1b010000-0000-0000-0000-000000000013'
\set missingID '1b010000-0000-0000-0000-000000000008'
\set namedUserID '1b010000-0000-0000-0000-000000000009'
\set regionID '1b010000-0000-0000-0000-000000000010'
\set sessionProposalID '1b010000-0000-0000-0000-000000000011'
\set unnamedUserID '1b010000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose display name is resolved
select fx_community(:'communityID', jsonb_build_object('display_name', 'Resource Name Community'));

-- User with a display name
select fx_user(:'namedUserID', jsonb_build_object('name', 'Resource Name User', 'username', 'resource-name-named'));

-- User without a display name
select fx_user(:'unnamedUserID', jsonb_build_object('username', 'resource-name-unnamed'));

-- Event category whose name is resolved
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'Resource Name Event Category'));

-- Group category whose name is resolved
select fx_group_category(:'groupCategoryID', :'communityID', jsonb_build_object('name', 'Resource Name Group Category'));

-- Region whose name is resolved
insert into region (region_id, community_id, name)
values (:'regionID', :'communityID', 'Resource Name Region');

-- Session proposal whose title is resolved
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'sessionProposalID',
    'Resource name proposal',
    make_interval(mins => 30),
    'beginner',
    'Resource Name Proposal',
    :'namedUserID'
);

-- Group whose name is resolved
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Resource Name Group'));

-- Event whose name is resolved
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('name', 'Resource Name Event'));

-- Group sponsor whose name is resolved
insert into group_sponsor (group_sponsor_id, group_id, logo_url, name)
values (:'groupSponsorID', :'groupID', 'https://example.test/logo.png', 'Resource Name Sponsor');

-- Inbox conversation resolved through its group name
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'inboxConversationID', :'groupID', :'namedUserID');

-- CFS submission resolved through its session proposal title
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'cfsSubmissionID', :'eventID', :'sessionProposalID', 'not-reviewed');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should resolve a CFS submission to its session proposal title
select is(
    audit_log_resource_name('cfs_submission', :'cfsSubmissionID'::uuid),
    'Resource Name Proposal',
    'Should resolve a CFS submission to its session proposal title'
);

-- Should resolve a community to its display name
select is(
    audit_log_resource_name('community', :'communityID'::uuid),
    'Resource Name Community',
    'Should resolve a community to its display name'
);

-- Should resolve a group to its name
select is(
    audit_log_resource_name('group', :'groupID'::uuid),
    'Resource Name Group',
    'Should resolve a group to its name'
);

-- Should resolve a group category to its name
select is(
    audit_log_resource_name('group_category', :'groupCategoryID'::uuid),
    'Resource Name Group Category',
    'Should resolve a group category to its name'
);

-- Should resolve a group sponsor to its name
select is(
    audit_log_resource_name('group_sponsor', :'groupSponsorID'::uuid),
    'Resource Name Sponsor',
    'Should resolve a group sponsor to its name'
);

-- Should resolve an inbox conversation to its group name
select is(
    audit_log_resource_name('inbox_conversation', :'inboxConversationID'::uuid),
    'Resource Name Group',
    'Should resolve an inbox conversation to its group name'
);

-- Should resolve a region to its name
select is(
    audit_log_resource_name('region', :'regionID'::uuid),
    'Resource Name Region',
    'Should resolve a region to its name'
);

-- Should resolve a session proposal to its title
select is(
    audit_log_resource_name('session_proposal', :'sessionProposalID'::uuid),
    'Resource Name Proposal',
    'Should resolve a session proposal to its title'
);

-- Should resolve a user to its display name
select is(
    audit_log_resource_name('user', :'namedUserID'::uuid),
    'Resource Name User',
    'Should resolve a user to its display name'
);

-- Should resolve a user without display name to its username
select is(
    audit_log_resource_name('user', :'unnamedUserID'::uuid),
    'resource-name-unnamed',
    'Should resolve a user without display name to its username'
);

-- Should resolve an event to its name
select is(
    audit_log_resource_name('event', :'eventID'::uuid),
    'Resource Name Event',
    'Should resolve an event to its name'
);

-- Should resolve an event category to its name
select is(
    audit_log_resource_name('event_category', :'eventCategoryID'::uuid),
    'Resource Name Event Category',
    'Should resolve an event category to its name'
);

-- Should return null for a missing resource row
select is(
    audit_log_resource_name('group', :'missingID'::uuid),
    null,
    'Should return null for a missing resource row'
);

-- Should return null for an unknown resource type
select is(
    audit_log_resource_name('unknown', :'groupID'::uuid),
    null,
    'Should return null for an unknown resource type'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
