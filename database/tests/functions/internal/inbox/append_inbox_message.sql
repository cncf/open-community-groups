-- Tests appending inbox messages and their conversation status transitions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '1b050000-0000-0000-0000-000000000008'
\set answeredConversationID '1b050000-0000-0000-0000-000000000001'
\set closedAnsweredConversationID '1b050000-0000-0000-0000-000000000002'
\set closedOpenConversationID '1b050000-0000-0000-0000-000000000003'
\set communityID '1b050000-0000-0000-0000-000000000004'
\set groupCategoryID '1b050000-0000-0000-0000-000000000005'
\set groupID '1b050000-0000-0000-0000-000000000006'
\set openConversationID '1b050000-0000-0000-0000-000000000007'
\set userID '1b050000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Actor replying on behalf of the group
select fx_user(:'actorID');

-- User writing to the group
select fx_user(:'userID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the conversations
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Answered conversation
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'answeredConversationID', :'groupID', 'answered', '2030-01-10 10:00:00+00', :'userID');

-- Closed conversation answered by a group reply
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'closedAnsweredConversationID', :'groupID', 'closed', '2030-01-10 10:00:00+00', :'userID');

-- Closed conversation reopened by the user
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'closedOpenConversationID', :'groupID', 'closed', '2030-01-10 10:00:00+00', :'userID');

-- Open conversation with a first message
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'openConversationID', :'groupID', 'open', '2030-01-10 10:00:00+00', :'userID');

-- First message of the open conversation
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id)
values ('Hello', '2030-01-10 10:00:00+00', :'openConversationID', 'initial', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should answer a closed conversation when the group replies
select lives_ok(
    format(
        $$select append_inbox_message(ic, %L::uuid, 'Reply', 'group-reply', '2030-01-10 11:00:00+00') from inbox_conversation ic where ic.inbox_conversation_id = %L::uuid$$,
        :'actorID',
        :'closedAnsweredConversationID'
    ),
    'Should append a group reply to a closed conversation'
);
select results_eq(
    format(
        $$select inbox_conversation_status_id, last_message_at from inbox_conversation where inbox_conversation_id = %L::uuid$$,
        :'closedAnsweredConversationID'
    ),
    $$values ('answered', '2030-01-10 11:00:00+00'::timestamptz)$$,
    'Should answer a closed conversation when the group replies'
);

-- Should answer an open conversation when the group replies
select lives_ok(
    format(
        $$select append_inbox_message(ic, %L::uuid, 'Reply', 'group-reply', '2030-01-10 11:00:00+00') from inbox_conversation ic where ic.inbox_conversation_id = %L::uuid$$,
        :'actorID',
        :'openConversationID'
    ),
    'Should append a group reply to an open conversation'
);
select results_eq(
    format(
        $$select inbox_conversation_status_id, last_message_at from inbox_conversation where inbox_conversation_id = %L::uuid$$,
        :'openConversationID'
    ),
    $$values ('answered', '2030-01-10 11:00:00+00'::timestamptz)$$,
    'Should answer an open conversation when the group replies'
);

-- Should keep the last message time when an older message is appended
select lives_ok(
    format(
        $$select append_inbox_message(ic, %L::uuid, 'Late', 'user-reply', '2030-01-10 09:00:00+00') from inbox_conversation ic where ic.inbox_conversation_id = %L::uuid$$,
        :'userID',
        :'answeredConversationID'
    ),
    'Should append a user reply with an older timestamp'
);
select results_eq(
    format(
        $$select inbox_conversation_status_id, last_message_at from inbox_conversation where inbox_conversation_id = %L::uuid$$,
        :'answeredConversationID'
    ),
    $$values ('open', '2030-01-10 10:00:00+00'::timestamptz)$$,
    'Should open an answered conversation and keep its last message time when an older message is appended'
);

-- Should open a closed conversation when the user writes
select lives_ok(
    format(
        $$select append_inbox_message(ic, %L::uuid, E'\n  Again \t\n', 'user-reply', '2030-01-10 12:00:00+00') from inbox_conversation ic where ic.inbox_conversation_id = %L::uuid$$,
        :'userID',
        :'closedOpenConversationID'
    ),
    'Should append a user reply to a closed conversation'
);
select results_eq(
    format(
        $$select inbox_conversation_status_id, last_message_at from inbox_conversation where inbox_conversation_id = %L::uuid$$,
        :'closedOpenConversationID'
    ),
    $$values ('open', '2030-01-10 12:00:00+00'::timestamptz)$$,
    'Should open a closed conversation when the user writes'
);

-- Should reject a second first message
select throws_ok(
    format(
        $$select append_inbox_message(ic, %L::uuid, 'Again', 'initial', '2030-01-10 12:00:00+00') from inbox_conversation ic where ic.inbox_conversation_id = %L::uuid$$,
        :'userID',
        :'openConversationID'
    ),
    '23505',
    null,
    'Should reject a second first message'
);

-- Should store the trimmed message with its author, kind and time
select results_eq(
    format(
        $$select author_user_id, body, created_at, kind from inbox_message where inbox_conversation_id = %L::uuid$$,
        :'closedOpenConversationID'
    ),
    format(
        $$values (%L::uuid, 'Again', '2030-01-10 12:00:00+00'::timestamptz, 'user-reply')$$,
        :'userID'
    ),
    'Should store the trimmed message with its author, kind and time'
);

-- Should return the identifier of the stored message
select append_inbox_message(ic, :'userID'::uuid, 'More', 'user-reply', '2030-01-10 13:00:00+00') as "appendedMessageID"
from inbox_conversation ic
where ic.inbox_conversation_id = :'closedOpenConversationID' \gset
select is(
    (select body from inbox_message where inbox_message_id = :'appendedMessageID'),
    'More',
    'Should return the identifier of the stored message'
);
select is(
    (select count(*)::int from inbox_message where inbox_conversation_id = :'closedOpenConversationID'),
    2,
    'Should store one row per appended message'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
