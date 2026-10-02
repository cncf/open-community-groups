-- Tests listing groups available for user notification mutes.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedTeamGroupID '9e020000-0000-0000-0000-000000000001'
\set attendeeEventID '9e020000-0000-0000-0000-000000000002'
\set attendeeGroupID '9e020000-0000-0000-0000-000000000003'
\set cohostApprovedGroupID '9e020000-0000-0000-0000-000000000004'
\set cohostCanceledGroupID '9e020000-0000-0000-0000-000000000005'
\set cohostPendingGroupID '9e020000-0000-0000-0000-000000000006'
\set cohostRejectedGroupID '9e020000-0000-0000-0000-000000000007'
\set communityID '9e020000-0000-0000-0000-000000000008'
\set deletedEventGroupID '9e020000-0000-0000-0000-000000000009'
\set deletedEventID '9e020000-0000-0000-0000-000000000010'
\set deletedGroupID '9e020000-0000-0000-0000-000000000011'
\set deletedGroupMemberUserID '9e020000-0000-0000-0000-000000000012'
\set eventCategoryID '9e020000-0000-0000-0000-000000000013'
\set eventSpeakerEventID '9e020000-0000-0000-0000-000000000014'
\set eventSpeakerGroupID '9e020000-0000-0000-0000-000000000015'
\set groupCategoryID '9e020000-0000-0000-0000-000000000016'
\set inactiveCommunityGroupCategoryID '9e020000-0000-0000-0000-000000000017'
\set inactiveCommunityGroupID '9e020000-0000-0000-0000-000000000018'
\set inactiveCommunityID '9e020000-0000-0000-0000-000000000019'
\set inactiveGroupID '9e020000-0000-0000-0000-000000000020'
\set memberGroupID '9e020000-0000-0000-0000-000000000021'
\set pendingTeamGroupID '9e020000-0000-0000-0000-000000000022'
\set sessionID '9e020000-0000-0000-0000-000000000023'
\set sessionSpeakerEventID '9e020000-0000-0000-0000-000000000024'
\set sessionSpeakerGroupID '9e020000-0000-0000-0000-000000000025'
\set ticketTypeID '9e020000-0000-0000-0000-000000000026'
\set userID '9e020000-0000-0000-0000-000000000027'
\set waitlistEventID '9e020000-0000-0000-0000-000000000028'
\set waitlistGroupID '9e020000-0000-0000-0000-000000000029'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community containing available groups
select fx_community(:'communityID');

-- Inactive community containing an excluded group
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

-- Event category used by event-connected groups
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by active-community groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category used by the inactive-community group
select fx_group_category(:'inactiveCommunityGroupCategoryID', :'inactiveCommunityID');

-- User whose connected groups are listed
select fx_user(:'userID');

-- Separate user used by the deleted-group exclusion scenario
select fx_user(:'deletedGroupMemberUserID');

-- Group connected through accepted team membership
select fx_group(:'acceptedTeamGroupID', :'communityID', :'groupCategoryID');

-- Group connected through an attendee row
select fx_group(:'attendeeGroupID', :'communityID', :'groupCategoryID');

-- Group connected through approved co-hosting of an attended event
select fx_group(:'cohostApprovedGroupID', :'communityID', :'groupCategoryID');

-- Canceled co-host group excluded from the result
select fx_group(:'cohostCanceledGroupID', :'communityID', :'groupCategoryID');

-- Pending co-host group excluded from the result
select fx_group(:'cohostPendingGroupID', :'communityID', :'groupCategoryID');

-- Rejected co-host group excluded from the result
select fx_group(:'cohostRejectedGroupID', :'communityID', :'groupCategoryID');

-- Group connected only through a deleted event
select fx_group(:'deletedEventGroupID', :'communityID', :'groupCategoryID');

-- Deleted group excluded even when a user belongs to it
select fx_group(
    :'deletedGroupID',
    :'communityID',
    :'groupCategoryID',
    jsonb_build_object(
        'active', false,
        'deleted', true,
        'deleted_at', '2024-01-01 00:00:00+00'
    )
);

-- Group connected through event speaking
select fx_group(:'eventSpeakerGroupID', :'communityID', :'groupCategoryID');

-- Group excluded because its community is inactive
select fx_group(:'inactiveCommunityGroupID', :'inactiveCommunityID', :'inactiveCommunityGroupCategoryID');

-- Inactive group excluded even when a user belongs to it
select fx_group(
    :'inactiveGroupID',
    :'communityID',
    :'groupCategoryID',
    jsonb_build_object('active', false)
);

-- Group connected through membership
select fx_group(:'memberGroupID', :'communityID', :'groupCategoryID');

-- Pending team group excluded from the result
select fx_group(:'pendingTeamGroupID', :'communityID', :'groupCategoryID');

-- Group connected through session speaking
select fx_group(:'sessionSpeakerGroupID', :'communityID', :'groupCategoryID');

-- Group connected through an event waitlist row
select fx_group(:'waitlistGroupID', :'communityID', :'groupCategoryID');

-- Attended event with approved and unavailable co-host states
select fx_event(:'attendeeEventID', :'attendeeGroupID', :'eventCategoryID');

-- Deleted event whose group should not be returned
select fx_event(:'deletedEventID', :'deletedEventGroupID', :'eventCategoryID', jsonb_build_object('deleted', true));

-- Event connected through event speaker
select fx_event(:'eventSpeakerEventID', :'eventSpeakerGroupID', :'eventCategoryID');

-- Event connected through session speaker
select fx_event(:'sessionSpeakerEventID', :'sessionSpeakerGroupID', :'eventCategoryID');

-- Event connected through waitlist
select fx_event(:'waitlistEventID', :'waitlistGroupID', :'eventCategoryID');

-- Ticket type required by the waitlist row
select fx_event_ticket_type(:'ticketTypeID', :'waitlistEventID');

-- Accepted team membership connection
insert into group_team (group_id, user_id, accepted, role)
values (:'acceptedTeamGroupID', :'userID', true, 'admin');

-- Pending team membership excluded from connections
insert into group_team (group_id, user_id, accepted, role)
values (:'pendingTeamGroupID', :'userID', false, 'admin');

-- Direct group membership connection
insert into group_member (group_id, user_id)
values (:'memberGroupID', :'userID');

-- Deleted group membership excluded from the result
insert into group_member (group_id, user_id)
values (:'deletedGroupID', :'deletedGroupMemberUserID');

-- Inactive community group membership excluded from the result
insert into group_member (group_id, user_id)
values (:'inactiveCommunityGroupID', :'userID');

-- Inactive group membership excluded from the result
insert into group_member (group_id, user_id)
values (:'inactiveGroupID', :'userID');

-- Attendee connection to the event owner and approved co-host groups
insert into event_attendee (event_id, user_id, status)
values (:'attendeeEventID', :'userID', 'confirmed');

-- Attendee row on a deleted event excluded from connections
insert into event_attendee (event_id, user_id, status)
values (:'deletedEventID', :'userID', 'confirmed');

-- Waitlist connection to an event owner group
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'waitlistEventID', :'ticketTypeID', :'userID');

-- Event speaker connection to an event owner group
insert into event_speaker (event_id, user_id)
values (:'eventSpeakerEventID', :'userID');

-- Session row for the session speaker connection
insert into session (event_id, name, session_id, session_kind_id, starts_at)
values (:'sessionSpeakerEventID', 'Notification Preferences', :'sessionID', 'in-person', '2030-01-01 10:00:00+00');

-- Session speaker connection to an event owner group
insert into session_speaker (session_id, user_id)
values (:'sessionID', :'userID');

-- Approved co-host group connected through the attended event
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id)
values ('2025-01-01 00:00:00+00', 'approved', :'attendeeEventID', :'cohostApprovedGroupID');

-- Canceled co-host group excluded from connections
insert into event_cohost (event_cohost_status_id, event_id, group_id)
values ('canceled', :'attendeeEventID', :'cohostCanceledGroupID');

-- Pending co-host group excluded from connections
insert into event_cohost (event_cohost_status_id, event_id, group_id)
values ('pending', :'attendeeEventID', :'cohostPendingGroupID');

-- Rejected co-host group excluded from connections
insert into event_cohost (event_cohost_status_id, event_id, group_id)
values ('rejected', :'attendeeEventID', :'cohostRejectedGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return every available connected group once
select is(
    list_user_notification_group_ids(:'userID'),
    array[
        :'acceptedTeamGroupID',
        :'attendeeGroupID',
        :'cohostApprovedGroupID',
        :'eventSpeakerGroupID',
        :'memberGroupID',
        :'sessionSpeakerGroupID',
        :'waitlistGroupID'
    ]::uuid[],
    'Should return every available connected group once'
);

-- Should return no unavailable connected groups
select is(
    list_user_notification_group_ids(:'deletedGroupMemberUserID'),
    '{}'::uuid[],
    'Should return no unavailable connected groups'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
