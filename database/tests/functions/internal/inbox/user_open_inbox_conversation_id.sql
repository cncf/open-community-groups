-- Tests finding the open inbox conversation of a user about an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f6a30000-0000-0000-0000-000000000001'
\set conversationAnsweredID 'f6a30000-0000-0000-0000-000000000002'
\set conversationClosedID 'f6a30000-0000-0000-0000-000000000003'
\set conversationOpenEarlierID 'f6a30000-0000-0000-0000-000000000004'
\set conversationOpenLatestID 'f6a30000-0000-0000-0000-000000000005'
\set conversationOtherUserID 'f6a30000-0000-0000-0000-000000000006'
\set conversationSpamID 'f6a30000-0000-0000-0000-000000000007'
\set conversationTieHigherID 'f6a30000-0000-0000-0000-000000000009'
\set conversationTieLowerID 'f6a30000-0000-0000-0000-000000000008'
\set eventCategoryID 'f6a30000-0000-0000-0000-000000000010'
\set eventID 'f6a30000-0000-0000-0000-000000000011'
\set eventNotOpenID 'f6a30000-0000-0000-0000-000000000012'
\set eventOtherUserID 'f6a30000-0000-0000-0000-000000000013'
\set eventTieID 'f6a30000-0000-0000-0000-000000000014'
\set eventWithoutConversationsID 'f6a30000-0000-0000-0000-000000000015'
\set groupCategoryID 'f6a30000-0000-0000-0000-000000000016'
\set groupID 'f6a30000-0000-0000-0000-000000000017'
\set otherGroupID 'f6a30000-0000-0000-0000-000000000018'
\set otherUserID 'f6a30000-0000-0000-0000-000000000019'
\set userID 'f6a30000-0000-0000-0000-000000000020'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Another user with an open conversation
select fx_user(:'otherUserID');

-- User whose open conversations are looked up
select fx_user(:'userID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Another group
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Event with several open conversations of the user
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Event whose conversations of the user are not open
select fx_event(:'eventNotOpenID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Event with an open conversation of another user only
select fx_event(:'eventOtherUserID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Event with two open conversations of the user active at the same time
select fx_event(:'eventTieID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Event without conversations
select fx_event(:'eventWithoutConversationsID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Answered conversation of the user with the latest activity
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, event_id, user_id)
values (:'conversationAnsweredID', '2030-01-01 10:00:00+00', :'groupID', 'answered', '2030-01-10 16:00:00+00', :'eventNotOpenID', :'userID');

-- Closed conversation of the user
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, event_id, user_id)
values (:'conversationClosedID', '2030-01-01 10:00:00+00', :'groupID', 'closed', '2030-01-10 15:00:00+00', :'eventNotOpenID', :'userID');

-- Open conversation of the user created last and active earlier
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, event_id, user_id)
values (:'conversationOpenEarlierID', '2030-01-02 10:00:00+00', :'groupID', 'open', '2030-01-10 10:00:00+00', :'eventID', :'userID');

-- Open conversation of the user created first and active most recently
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, event_id, user_id)
values (:'conversationOpenLatestID', '2030-01-01 10:00:00+00', :'groupID', 'open', '2030-01-10 11:00:00+00', :'eventID', :'userID');

-- Open conversation of another user
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, event_id, user_id)
values (:'conversationOtherUserID', '2030-01-01 10:00:00+00', :'groupID', 'open', '2030-01-10 10:00:00+00', :'eventOtherUserID', :'otherUserID');

-- Conversation of the user marked as spam
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, event_id, user_id)
values (:'conversationSpamID', '2030-01-01 10:00:00+00', :'groupID', 'spam', '2030-01-10 14:00:00+00', :'eventNotOpenID', :'userID');

-- Open conversation of the user with the higher identifier of the tie
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, event_id, user_id)
values (:'conversationTieHigherID', '2030-01-01 10:00:00+00', :'groupID', 'open', '2030-01-10 12:00:00+00', :'eventTieID', :'userID');

-- Open conversation of the user with the lower identifier of the tie
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, event_id, user_id)
values (:'conversationTieLowerID', '2030-01-02 10:00:00+00', :'groupID', 'open', '2030-01-10 12:00:00+00', :'eventTieID', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should break activity ties by the highest conversation identifier
select is(
    user_open_inbox_conversation_id(:'groupID'::uuid, :'eventTieID'::uuid, :'userID'::uuid),
    :'conversationTieHigherID'::uuid,
    'Should break activity ties by the highest conversation identifier'
);

-- Should ignore conversations of other groups
select is(
    user_open_inbox_conversation_id(:'otherGroupID'::uuid, :'eventID'::uuid, :'userID'::uuid),
    null::uuid,
    'Should ignore conversations of other groups'
);

-- Should ignore conversations of other users
select is(
    user_open_inbox_conversation_id(:'groupID'::uuid, :'eventOtherUserID'::uuid, :'userID'::uuid),
    null::uuid,
    'Should ignore conversations of other users'
);

-- Should ignore conversations that are answered, closed or marked as spam
select is(
    user_open_inbox_conversation_id(:'groupID'::uuid, :'eventNotOpenID'::uuid, :'userID'::uuid),
    null::uuid,
    'Should ignore conversations that are answered, closed or marked as spam'
);

-- Should return null when the user only has open conversations about other events
select is(
    user_open_inbox_conversation_id(:'groupID'::uuid, :'eventWithoutConversationsID'::uuid, :'userID'::uuid),
    null::uuid,
    'Should return null when the user only has open conversations about other events'
);

-- Should return the most recently active open conversation about the event
select is(
    user_open_inbox_conversation_id(:'groupID'::uuid, :'eventID'::uuid, :'userID'::uuid),
    :'conversationOpenLatestID'::uuid,
    'Should return the most recently active open conversation about the event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
