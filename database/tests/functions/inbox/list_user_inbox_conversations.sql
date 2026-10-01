-- Tests listing the inbox conversations of a user.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1b100000-0000-0000-0000-000000000001'
\set conversationClosedID '1b100000-0000-0000-0000-000000000002'
\set conversationOpenID '1b100000-0000-0000-0000-000000000003'
\set conversationOtherID '1b100000-0000-0000-0000-000000000004'
\set groupCategoryID '1b100000-0000-0000-0000-000000000005'
\set groupID '1b100000-0000-0000-0000-000000000006'
\set otherGroupID '1b100000-0000-0000-0000-000000000007'
\set otherUserID '1b100000-0000-0000-0000-000000000008'
\set userID '1b100000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Another user
select fx_user(:'otherUserID');

-- User who wrote to the group
select fx_user(:'userID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group contacted by the user
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Another group contacted by another user
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Closed conversation of the user with the group
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'conversationClosedID', :'groupID', 'closed', '2020-01-10 10:00:00+00', :'userID');

-- Open conversation of the user with the group
insert into inbox_conversation (inbox_conversation_id, group_id, last_message_at, user_id)
values (:'conversationOpenID', :'groupID', '2020-01-10 11:00:00+00', :'userID');

-- Conversation of another user with another group
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationOtherID', :'otherGroupID', :'otherUserID');

-- First messages of the conversations
insert into inbox_message (body, inbox_conversation_id, kind) values
    ('Closed', :'conversationClosedID', 'initial'),
    ('Open', :'conversationOpenID', 'initial'),
    ('Other', :'conversationOtherID', 'initial');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should forward the filters to the search
select is(
    jsonb_path_query_array(list_user_inbox_conversations(:'userID'::uuid, '{"status": "closed"}'::jsonb)::jsonb, '$.conversations[*].inbox_conversation_id'),
    jsonb_build_array(:'conversationClosedID'::uuid),
    'Should forward the filters to the search'
);

-- Should list the conversations of the user by latest activity
select is(
    (
        select jsonb_build_object(
            'ids', jsonb_path_query_array(r, '$.conversations[*].inbox_conversation_id'),
            'total', r->'total'
        )
        from (select list_user_inbox_conversations(:'userID'::uuid, '{}'::jsonb)::jsonb as r) t
    ),
    jsonb_build_object(
        'ids', jsonb_build_array(:'conversationOpenID'::uuid, :'conversationClosedID'::uuid),
        'total', 2
    ),
    'Should list the conversations of the user by latest activity'
);

-- Should keep the conversations of other users apart
select is(
    jsonb_path_query_array(list_user_inbox_conversations(:'otherUserID'::uuid, '{}'::jsonb)::jsonb, '$.conversations[*].inbox_conversation_id'),
    jsonb_build_array(:'conversationOtherID'::uuid),
    'Should keep the conversations of other users apart'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
