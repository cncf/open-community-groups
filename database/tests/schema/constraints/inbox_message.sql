-- Tests inbox message constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c0040000-0000-0000-0000-000000000001'
\set conversationID 'c0040000-0000-0000-0000-000000000002'
\set groupCategoryID 'c0040000-0000-0000-0000-000000000003'
\set groupID 'c0040000-0000-0000-0000-000000000004'
\set initialMessageID 'c0040000-0000-0000-0000-000000000005'
\set replyMessageID 'c0040000-0000-0000-0000-000000000006'
\set userID 'c0040000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- User deleted by the user deletion scenario
select fx_user(:'userID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the conversation
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Conversation started by the deleted user
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationID', :'groupID', :'userID');

-- Initial message written by the deleted user
insert into inbox_message (inbox_message_id, body, inbox_conversation_id, kind, author_user_id)
values (:'initialMessageID', 'Hello organizers', :'conversationID', 'initial', :'userID');

-- Follow-up message written by the deleted user
insert into inbox_message (inbox_message_id, body, inbox_conversation_id, kind, author_user_id)
values (:'replyMessageID', 'Any update?', :'conversationID', 'user-reply', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep the messages and clear their author when the user is deleted
select lives_ok(
    format($$delete from "user" where user_id = %L::uuid$$, :'userID'),
    'Should delete a user referenced by inbox messages'
);
select results_eq(
    format(
        $$select author_user_id, body from inbox_message where inbox_conversation_id = %L::uuid order by body$$,
        :'conversationID'
    ),
    $$values (null::uuid, 'Any update?'), (null::uuid, 'Hello organizers')$$,
    'Should keep the messages and clear their author when the user is deleted'
);

-- Should reject a body longer than 5000 characters
select throws_ok(
    format(
        $$insert into inbox_message (body, inbox_conversation_id, kind) values (repeat('é', 5001), %L::uuid, 'user-reply')$$,
        :'conversationID'
    ),
    '23514',
    null,
    'Should reject a body longer than 5000 characters'
);

-- Should reject a second initial message in a conversation
select throws_ok(
    format(
        $$insert into inbox_message (body, inbox_conversation_id, kind) values ('Again', %L::uuid, 'initial')$$,
        :'conversationID'
    ),
    '23505',
    null,
    'Should reject a second initial message in a conversation'
);

-- Should reject a whitespace-only body
select throws_ok(
    format(
        $$insert into inbox_message (body, inbox_conversation_id, kind) values (E' \t\n', %L::uuid, 'user-reply')$$,
        :'conversationID'
    ),
    '23514',
    null,
    'Should reject a whitespace-only body'
);

-- Should reject an unknown message kind
select throws_ok(
    format(
        $$insert into inbox_message (body, inbox_conversation_id, kind) values ('Hi', %L::uuid, 'note')$$,
        :'conversationID'
    ),
    '23514',
    null,
    'Should reject an unknown message kind'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
