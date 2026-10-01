-- Tests loading inbox conversation threads in the group scope.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1b0d0000-0000-0000-0000-000000000001'
\set conversationID '1b0d0000-0000-0000-0000-000000000002'
\set groupCategoryID '1b0d0000-0000-0000-0000-000000000003'
\set groupID '1b0d0000-0000-0000-0000-000000000004'
\set otherGroupID '1b0d0000-0000-0000-0000-000000000005'
\set userID '1b0d0000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- User who wrote to the group
select fx_user(:'userID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the conversation
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Another group
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Conversation of the group
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationID', :'groupID', :'userID');

-- First message of the conversation
insert into inbox_message (body, inbox_conversation_id, kind, author_user_id)
values ('Hello', :'conversationID', 'initial', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return null for a conversation of another group
select is(
    get_group_inbox_conversation(:'otherGroupID'::uuid, :'conversationID'::uuid)::jsonb,
    null,
    'Should return null for a conversation of another group'
);

-- Should return the thread of a conversation of the group
select is(
    get_group_inbox_conversation(:'groupID'::uuid, :'conversationID'::uuid)::jsonb,
    inbox_conversation_json(:'conversationID'::uuid)::jsonb,
    'Should return the thread of a conversation of the group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
