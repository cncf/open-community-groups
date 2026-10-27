-- Tests locking inbox conversations within their group.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f6a10000-0000-0000-0000-000000000001'
\set conversationID 'f6a10000-0000-0000-0000-000000000002'
\set conversationOtherGroupID 'f6a10000-0000-0000-0000-000000000003'
\set groupCategoryID 'f6a10000-0000-0000-0000-000000000004'
\set groupID 'f6a10000-0000-0000-0000-000000000005'
\set otherGroupID 'f6a10000-0000-0000-0000-000000000006'
\set unknownConversationID 'f6a10000-0000-0000-0000-000000000007'
\set userID 'f6a10000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- User who wrote to the groups
select fx_user(:'userID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the conversation
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Another group
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Answered conversation of the group
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'conversationID', :'groupID', 'answered', '2030-01-10 10:00:00+00', :'userID');

-- Conversation of another group
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationOtherGroupID', :'otherGroupID', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should lock the conversation row for update
-- Take the lock within this scenario before reading the row's xmax
select (lock_group_inbox_conversation(:'groupID', :'conversationID')).inbox_conversation_id as "lockedConversationID" \gset

select is(
    (select xmax::text from inbox_conversation where inbox_conversation_id = :'conversationID'),
    (pg_current_xact_id()::text::bigint % 4294967296)::text,
    'Should lock the conversation row for update'
);

-- Should reject conversations of other groups
select throws_ok(
    format($$select lock_group_inbox_conversation(%L::uuid, %L::uuid)$$, :'groupID', :'conversationOtherGroupID'),
    'OCG01',
    'conversation not found',
    'Should reject conversations of other groups'
);

-- Should reject unknown conversations
select throws_ok(
    format($$select lock_group_inbox_conversation(%L::uuid, %L::uuid)$$, :'groupID', :'unknownConversationID'),
    'OCG01',
    'conversation not found',
    'Should reject unknown conversations'
);

-- Should return the conversation row
select results_eq(
    format(
        $$select (lock_group_inbox_conversation(%L::uuid, %L::uuid)).*$$,
        :'groupID',
        :'conversationID'
    ),
    format(
        $$select * from inbox_conversation where inbox_conversation_id = %L::uuid$$,
        :'conversationID'
    ),
    'Should return the conversation row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
