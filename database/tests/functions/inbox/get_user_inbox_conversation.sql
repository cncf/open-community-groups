-- Tests loading inbox conversation threads in the user scope.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1b0e0000-0000-0000-0000-000000000001'
\set conversationDeletedGroupID '1b0e0000-0000-0000-0000-000000000002'
\set conversationID '1b0e0000-0000-0000-0000-000000000003'
\set deletedGroupID '1b0e0000-0000-0000-0000-000000000004'
\set groupCategoryID '1b0e0000-0000-0000-0000-000000000005'
\set groupID '1b0e0000-0000-0000-0000-000000000006'
\set otherUserID '1b0e0000-0000-0000-0000-000000000007'
\set userID '1b0e0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Another user
select fx_user(:'otherUserID');

-- User owning the conversations
select fx_user(:'userID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group contacted by the user
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Deleted group contacted by the user
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Conversation of the user in the deleted group
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationDeletedGroupID', :'deletedGroupID', :'userID');

-- Conversation of the user
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationID', :'groupID', :'userID');

-- First message of the conversation
insert into inbox_message (body, inbox_conversation_id, kind, author_user_id)
values ('Hello', :'conversationID', 'initial', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return null for a conversation of a deleted group
select is(
    get_user_inbox_conversation(:'userID'::uuid, :'conversationDeletedGroupID'::uuid)::jsonb,
    null,
    'Should return null for a conversation of a deleted group'
);

-- Should return null for a conversation of another user
select is(
    get_user_inbox_conversation(:'otherUserID'::uuid, :'conversationID'::uuid)::jsonb,
    null,
    'Should return null for a conversation of another user'
);

-- Should return the thread of a conversation of the user
select is(
    get_user_inbox_conversation(:'userID'::uuid, :'conversationID'::uuid)::jsonb,
    inbox_conversation_json(:'conversationID'::uuid)::jsonb,
    'Should return the thread of a conversation of the user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
