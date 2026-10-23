-- Tests resolving audit log resource display names.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(31);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set admissionOfferID '1b010000-0000-0000-0000-000000000015'
\set badgeArtworkID '1b010000-0000-0000-0000-000000000016'
\set badgeID '1b010000-0000-0000-0000-000000000017'
\set badgeStatusListID '1b010000-0000-0000-0000-000000000018'
\set cfsSubmissionID '1b010000-0000-0000-0000-000000000001'
\set communityID '1b010000-0000-0000-0000-000000000002'
\set eventCategoryID '1b010000-0000-0000-0000-000000000003'
\set eventID '1b010000-0000-0000-0000-000000000004'
\set eventSurveyID '1b010000-0000-0000-0000-000000000014'
\set eventTicketTypeID '1b010000-0000-0000-0000-000000000019'
\set groupCategoryID '1b010000-0000-0000-0000-000000000005'
\set groupID '1b010000-0000-0000-0000-000000000006'
\set groupSponsorID '1b010000-0000-0000-0000-000000000007'
\set inboxConversationID '1b010000-0000-0000-0000-000000000013'
\set missingID '1b010000-0000-0000-0000-000000000008'
\set namedUserBadgeID '1b010000-0000-0000-0000-000000000020'
\set namedUserID '1b010000-0000-0000-0000-000000000009'
\set regionID '1b010000-0000-0000-0000-000000000010'
\set revokedUserBadgeID '1b010000-0000-0000-0000-000000000021'
\set sessionProposalID '1b010000-0000-0000-0000-000000000011'
\set unnamedAdmissionOfferID '1b010000-0000-0000-0000-000000000022'
\set unnamedUserBadgeID '1b010000-0000-0000-0000-000000000023'
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

-- Badge whose name is resolved
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (
    :'badgeID',
    'Attend the event',
    'Resource name badge',
    :'groupID',
    'resource-name-badge.png',
    'Resource Name Badge'
);

-- Badge artwork whose file name is resolved
insert into badge_artwork (badge_artwork_id, file_name, group_id)
values (:'badgeArtworkID', 'resource-name-artwork.png', :'groupID');

-- Status list holding the badge awards
insert into badge_status_list (badge_status_list_id, group_id)
values (:'badgeStatusListID', :'groupID');

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

-- Event survey whose title is resolved
insert into event_survey (event_survey_id, event_id, title)
values (:'eventSurveyID', :'eventID', 'Resource Name Survey');

-- Ticket type offered to the ticket offer recipients
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID');

-- Badge awards resolved through a named, an unnamed and a deleted recipient
insert into user_badge (
    user_badge_id,
    badge_status_list_id,
    display_order,
    group_id,
    snapshot,
    status_list_index,

    badge_id,
    revoked_at,
    user_id
) values (
    :'namedUserBadgeID',
    :'badgeStatusListID',
    0,
    :'groupID',
    '{"name": "Resource Name Badge Snapshot"}',
    0,

    :'badgeID',
    null,
    :'namedUserID'
), (
    :'unnamedUserBadgeID',
    :'badgeStatusListID',
    0,
    :'groupID',
    '{"name": "Resource Name Badge Snapshot"}',
    1,

    :'badgeID',
    null,
    :'unnamedUserID'
), (
    :'revokedUserBadgeID',
    :'badgeStatusListID',
    0,
    :'groupID',
    '{"name": "Resource Name Badge Snapshot"}',
    2,

    :'badgeID',
    '2024-01-03 10:00:00+00',
    null
);

-- Expired ticket offers resolved through a named and an unnamed recipient
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'admissionOfferID',
    '2024-01-01 10:00:00+00',
    :'eventID',
    :'eventTicketTypeID',
    '2024-01-02 10:00:00+00',
    'waitlist',
    'expired',
    :'namedUserID'
), (
    :'unnamedAdmissionOfferID',
    '2024-01-01 10:00:00+00',
    :'eventID',
    :'eventTicketTypeID',
    '2024-01-02 10:00:00+00',
    'waitlist',
    'expired',
    :'unnamedUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should prefer the live name over the recorded name
select is(
    audit_log_resource_name('region', :'regionID'::uuid, '{"name": "Recorded Region"}'::jsonb),
    'Resource Name Region',
    'Should prefer the live name over the recorded name'
);

-- Should resolve a badge artwork to its file name
select is(
    audit_log_resource_name('badge_artwork', :'badgeArtworkID'::uuid, '{}'::jsonb),
    'resource-name-artwork.png',
    'Should resolve a badge artwork to its file name'
);

-- Should resolve a badge award to its recipient display name
select is(
    audit_log_resource_name('user_badge', :'namedUserBadgeID'::uuid, '{}'::jsonb),
    'Resource Name User',
    'Should resolve a badge award to its recipient display name'
);

-- Should resolve a badge award whose recipient is gone to its badge name
select is(
    audit_log_resource_name('user_badge', :'revokedUserBadgeID'::uuid, '{}'::jsonb),
    'Resource Name Badge Snapshot',
    'Should resolve a badge award whose recipient is gone to its badge name'
);

-- Should resolve a badge award without recipient display name to its username
select is(
    audit_log_resource_name('user_badge', :'unnamedUserBadgeID'::uuid, '{}'::jsonb),
    'resource-name-unnamed',
    'Should resolve a badge award without recipient display name to its username'
);

-- Should resolve a badge to its name
select is(
    audit_log_resource_name('badge', :'badgeID'::uuid, '{}'::jsonb),
    'Resource Name Badge',
    'Should resolve a badge to its name'
);

-- Should resolve a CFS submission to its session proposal title
select is(
    audit_log_resource_name('cfs_submission', :'cfsSubmissionID'::uuid, '{}'::jsonb),
    'Resource Name Proposal',
    'Should resolve a CFS submission to its session proposal title'
);

-- Should resolve a community to its display name
select is(
    audit_log_resource_name('community', :'communityID'::uuid, '{}'::jsonb),
    'Resource Name Community',
    'Should resolve a community to its display name'
);

-- Should resolve a deleted badge artwork to its recorded file name
select is(
    audit_log_resource_name('badge_artwork', :'missingID'::uuid, '{"file_name": "recorded-artwork.png"}'::jsonb),
    'recorded-artwork.png',
    'Should resolve a deleted badge artwork to its recorded file name'
);

-- Should resolve a deleted badge to its recorded name
select is(
    audit_log_resource_name('badge', :'missingID'::uuid, '{"badge_name": "Recorded Badge"}'::jsonb),
    'Recorded Badge',
    'Should resolve a deleted badge to its recorded name'
);

-- Should resolve a deleted event category to its recorded name
select is(
    audit_log_resource_name('event_category', :'missingID'::uuid, '{"name": "Recorded Event Category"}'::jsonb),
    'Recorded Event Category',
    'Should resolve a deleted event category to its recorded name'
);

-- Should resolve a deleted event survey to its recorded title
select is(
    audit_log_resource_name('event_survey', :'missingID'::uuid, '{"title": "Recorded Survey"}'::jsonb),
    'Recorded Survey',
    'Should resolve a deleted event survey to its recorded title'
);

-- Should resolve a deleted group category to its recorded name
select is(
    audit_log_resource_name('group_category', :'missingID'::uuid, '{"name": "Recorded Group Category"}'::jsonb),
    'Recorded Group Category',
    'Should resolve a deleted group category to its recorded name'
);

-- Should resolve a deleted group sponsor to its recorded name
select is(
    audit_log_resource_name('group_sponsor', :'missingID'::uuid, '{"name": "Recorded Sponsor"}'::jsonb),
    'Recorded Sponsor',
    'Should resolve a deleted group sponsor to its recorded name'
);

-- Should resolve a deleted region to its recorded name
select is(
    audit_log_resource_name('region', :'missingID'::uuid, '{"name": "Recorded Region"}'::jsonb),
    'Recorded Region',
    'Should resolve a deleted region to its recorded name'
);

-- Should resolve a deleted session proposal to its recorded title
select is(
    audit_log_resource_name('session_proposal', :'missingID'::uuid, '{"title": "Recorded Proposal"}'::jsonb),
    'Recorded Proposal',
    'Should resolve a deleted session proposal to its recorded title'
);

-- Should resolve a group category to its name
select is(
    audit_log_resource_name('group_category', :'groupCategoryID'::uuid, '{}'::jsonb),
    'Resource Name Group Category',
    'Should resolve a group category to its name'
);

-- Should resolve a group sponsor to its name
select is(
    audit_log_resource_name('group_sponsor', :'groupSponsorID'::uuid, '{}'::jsonb),
    'Resource Name Sponsor',
    'Should resolve a group sponsor to its name'
);

-- Should resolve a group to its name
select is(
    audit_log_resource_name('group', :'groupID'::uuid, '{}'::jsonb),
    'Resource Name Group',
    'Should resolve a group to its name'
);

-- Should resolve a region to its name
select is(
    audit_log_resource_name('region', :'regionID'::uuid, '{}'::jsonb),
    'Resource Name Region',
    'Should resolve a region to its name'
);

-- Should resolve a session proposal to its title
select is(
    audit_log_resource_name('session_proposal', :'sessionProposalID'::uuid, '{}'::jsonb),
    'Resource Name Proposal',
    'Should resolve a session proposal to its title'
);

-- Should resolve a ticket offer to its recipient display name
select is(
    audit_log_resource_name('admission_offer', :'admissionOfferID'::uuid, '{}'::jsonb),
    'Resource Name User',
    'Should resolve a ticket offer to its recipient display name'
);

-- Should resolve a ticket offer without recipient display name to its username
select is(
    audit_log_resource_name('admission_offer', :'unnamedAdmissionOfferID'::uuid, '{}'::jsonb),
    'resource-name-unnamed',
    'Should resolve a ticket offer without recipient display name to its username'
);

-- Should resolve a user to its display name
select is(
    audit_log_resource_name('user', :'namedUserID'::uuid, '{}'::jsonb),
    'Resource Name User',
    'Should resolve a user to its display name'
);

-- Should resolve a user without display name to its username
select is(
    audit_log_resource_name('user', :'unnamedUserID'::uuid, '{}'::jsonb),
    'resource-name-unnamed',
    'Should resolve a user without display name to its username'
);

-- Should resolve an event category to its name
select is(
    audit_log_resource_name('event_category', :'eventCategoryID'::uuid, '{}'::jsonb),
    'Resource Name Event Category',
    'Should resolve an event category to its name'
);

-- Should resolve an event survey to its title
select is(
    audit_log_resource_name('event_survey', :'eventSurveyID'::uuid, '{}'::jsonb),
    'Resource Name Survey',
    'Should resolve an event survey to its title'
);

-- Should resolve an event to its name
select is(
    audit_log_resource_name('event', :'eventID'::uuid, '{}'::jsonb),
    'Resource Name Event',
    'Should resolve an event to its name'
);

-- Should resolve an inbox conversation to its group name
select is(
    audit_log_resource_name('inbox_conversation', :'inboxConversationID'::uuid, '{}'::jsonb),
    'Resource Name Group',
    'Should resolve an inbox conversation to its group name'
);

-- Should return null for a missing resource whose type has no recorded fallback
select is(
    audit_log_resource_name('group', :'missingID'::uuid, '{"name": "Recorded Group"}'::jsonb),
    null,
    'Should return null for a missing resource whose type has no recorded fallback'
);

-- Should return null for an unknown resource type
select is(
    audit_log_resource_name('unknown', :'groupID'::uuid, '{}'::jsonb),
    null,
    'Should return null for an unknown resource type'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
