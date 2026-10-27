-- Tests deriving the inbox conversation status a message kind implies.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should answer the conversation for group replies
select is(
    inbox_conversation_status_for_message_kind('group-reply'),
    'answered',
    'Should answer the conversation for group replies'
);

-- Should open the conversation for initial messages
select is(
    inbox_conversation_status_for_message_kind('initial'),
    'open',
    'Should open the conversation for initial messages'
);

-- Should open the conversation for user replies
select is(
    inbox_conversation_status_for_message_kind('user-reply'),
    'open',
    'Should open the conversation for user replies'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
