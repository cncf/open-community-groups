-- Tests loading the event page contact modal context.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1b080000-0000-0000-0000-000000000001'
\set conversationAnsweredID '1b080000-0000-0000-0000-000000000002'
\set conversationLimitedFirstID '1b080000-0000-0000-0000-000000000003'
\set conversationLimitedSecondID '1b080000-0000-0000-0000-000000000004'
\set conversationLimitedThirdID '1b080000-0000-0000-0000-000000000005'
\set conversationOpenEarlierID '1b080000-0000-0000-0000-000000000006'
\set conversationReopenedID '1b080000-0000-0000-0000-000000000007'
\set conversationSpamID '1b080000-0000-0000-0000-000000000017'
\set eventCategoryID '1b080000-0000-0000-0000-000000000008'
\set eventID '1b080000-0000-0000-0000-000000000009'
\set groupCategoryID '1b080000-0000-0000-0000-000000000010'
\set groupID '1b080000-0000-0000-0000-000000000011'
\set limitedUserID '1b080000-0000-0000-0000-000000000012'
\set otherGroupID '1b080000-0000-0000-0000-000000000014'
\set spamUserID '1b080000-0000-0000-0000-000000000018'
\set teamMemberID '1b080000-0000-0000-0000-000000000013'
\set unpublishedEventID '1b080000-0000-0000-0000-000000000015'
\set userID '1b080000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID', jsonb_build_object('name', 'inbox-contact-community'));

-- User who reached the daily limit of new conversations
select fx_user(:'limitedUserID');

-- User whose conversation the group marked as spam
select fx_user(:'spamUserID');

-- Accepted team member of the group
select fx_user(:'teamMemberID');

-- User with conversations in the group
select fx_user(:'userID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the event
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Inbox Contact Group',
    'slug', 'inbox-contact-group',
    'slug_pretty', 'inbox-contact'
));

-- Group contacted by the limited user
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Published event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Inbox Contact Event',
    'published', true,
    'slug', 'inbox-contact-event'
));

-- Unpublished event
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID');

-- Accepted admin membership of the team member
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'admin', :'teamMemberID');

-- Conversations started today by the limited user
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, user_id) values
    (:'conversationLimitedFirstID', current_timestamp - interval '3 hours', :'otherGroupID', 'answered', :'limitedUserID'),
    (:'conversationLimitedSecondID', current_timestamp - interval '2 hours', :'otherGroupID', 'answered', :'limitedUserID'),
    (:'conversationLimitedThirdID', current_timestamp - interval '1 hour', :'otherGroupID', 'answered', :'limitedUserID');

-- Answered conversation of the user with the latest activity
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'conversationAnsweredID', '2020-01-01 10:00:00+00', :'groupID', 'answered', '2020-01-10 12:00:00+00', :'userID');

-- Open conversation of the user opened before the reopened one was active again
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'conversationOpenEarlierID', '2020-01-02 10:00:00+00', :'groupID', 'open', '2020-01-10 10:00:00+00', :'userID');

-- Older conversation of the user reopened most recently
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'conversationReopenedID', '2020-01-01 09:00:00+00', :'groupID', 'open', '2020-01-10 11:00:00+00', :'userID');

-- Conversation of the spam user marked as spam by the group
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, user_id)
values (:'conversationSpamID', '2020-01-01 10:00:00+00', :'groupID', 'spam', :'spamUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should describe the event for anonymous visitors
select is(
    get_inbox_contact_context(:'communityID'::uuid, :'eventID'::uuid, null)::jsonb,
    format('{
        "community_name": "inbox-contact-community",
        "event_id": "%s",
        "event_name": "Inbox Contact Event",
        "event_slug": "inbox-contact-event",
        "group_name": "Inbox Contact Group",
        "group_slug": "inbox-contact-group",

        "group_slug_pretty": "inbox-contact"
    }', :'eventID')::jsonb,
    'Should describe the event for anonymous visitors'
);

-- Should flag users blocked by spam reports
select is(
    get_inbox_contact_context(:'communityID'::uuid, :'eventID'::uuid, :'spamUserID'::uuid)::jsonb->'viewer',
    '{"can_start_conversation": true, "is_blocked": true, "is_group_team_member": false}'::jsonb,
    'Should flag users blocked by spam reports'
);

-- Should flag group team members
select is(
    get_inbox_contact_context(:'communityID'::uuid, :'eventID'::uuid, :'teamMemberID'::uuid)::jsonb->'viewer',
    '{"can_start_conversation": true, "is_blocked": false, "is_group_team_member": true}'::jsonb,
    'Should flag group team members'
);

-- Should point to the most recently active open conversation
select is(
    get_inbox_contact_context(:'communityID'::uuid, :'eventID'::uuid, :'userID'::uuid)::jsonb->'viewer',
    format(
        '{"can_start_conversation": true, "is_blocked": false, "is_group_team_member": false, "open_inbox_conversation_id": "%s"}',
        :'conversationReopenedID'
    )::jsonb,
    'Should point to the most recently active open conversation'
);

-- Should report users who reached the daily limit of new conversations
select is(
    get_inbox_contact_context(:'communityID'::uuid, :'eventID'::uuid, :'limitedUserID'::uuid)::jsonb->'viewer',
    '{"can_start_conversation": false, "is_blocked": false, "is_group_team_member": false}'::jsonb,
    'Should report users who reached the daily limit of new conversations'
);

-- Should return null for events that do not accept contact
select is(
    get_inbox_contact_context(:'communityID'::uuid, :'unpublishedEventID'::uuid, :'userID'::uuid)::jsonb,
    null,
    'Should return null for events that do not accept contact'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
