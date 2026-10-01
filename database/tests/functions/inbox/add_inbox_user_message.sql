-- Tests adding user follow-up messages to inbox conversations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1b0a0000-0000-0000-0000-000000000001'
\set conversationAnsweredID '1b0a0000-0000-0000-0000-000000000002'
\set conversationClosedID '1b0a0000-0000-0000-0000-000000000003'
\set conversationDeletedGroupID '1b0a0000-0000-0000-0000-000000000004'
\set conversationLimitedID '1b0a0000-0000-0000-0000-000000000005'
\set conversationNearLimitID '1b0a0000-0000-0000-0000-000000000006'
\set conversationOtherUserID '1b0a0000-0000-0000-0000-000000000007'
\set conversationSpamID '1b0a0000-0000-0000-0000-000000000017'
\set deletedGroupID '1b0a0000-0000-0000-0000-000000000008'
\set eventCategoryID '1b0a0000-0000-0000-0000-000000000009'
\set eventID '1b0a0000-0000-0000-0000-000000000010'
\set groupCategoryID '1b0a0000-0000-0000-0000-000000000011'
\set groupID '1b0a0000-0000-0000-0000-000000000012'
\set limitedUserID '1b0a0000-0000-0000-0000-000000000013'
\set nearLimitUserID '1b0a0000-0000-0000-0000-000000000014'
\set otherUserID '1b0a0000-0000-0000-0000-000000000015'
\set userID '1b0a0000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- User who reached the daily message limit
select fx_user(:'limitedUserID');

-- User one message below the daily limit
select fx_user(:'nearLimitUserID');

-- User owning another conversation
select fx_user(:'otherUserID');

-- User sending follow-ups
select fx_user(:'userID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the conversations
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Deleted group
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Event the conversations started from
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Answered conversation of the user
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, last_message_at, event_id, user_id)
values (:'conversationAnsweredID', :'groupID', 'answered', '2020-01-10 10:00:00+00', :'eventID', :'userID');

-- Closed conversation of the user
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, last_message_at, event_id, user_id)
values (:'conversationClosedID', :'groupID', 'closed', '2020-01-10 10:00:00+00', :'eventID', :'userID');

-- Conversation of the user in the deleted group
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationDeletedGroupID', :'deletedGroupID', :'userID');

-- Conversation of the limited user
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationLimitedID', :'groupID', :'limitedUserID');

-- Conversation of the user below the limit
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationNearLimitID', :'groupID', :'nearLimitUserID');

-- Conversation of another user
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationOtherUserID', :'groupID', :'otherUserID');

-- Conversation of the user marked as spam, which blocks the user from the group
-- while their other conversations keep accepting follow-ups
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, user_id)
values (:'conversationSpamID', :'groupID', 'spam', :'userID');

-- Ten follow-ups sent today by the limited user
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id)
select 'Follow-up', current_timestamp - make_interval(mins => n), :'conversationLimitedID', 'user-reply', :'limitedUserID'
from generate_series(1, 10) n;

-- Nine follow-ups sent today by the user below the limit
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id)
select 'Follow-up', current_timestamp - make_interval(mins => n), :'conversationNearLimitID', 'user-reply', :'nearLimitUserID'
from generate_series(1, 9) n;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject conversations of deleted groups
select throws_ok(
    format($$select add_inbox_user_message(%L::uuid, %L::uuid, 'Hello')$$, :'userID', :'conversationDeletedGroupID'),
    'OCG01',
    'conversation not found',
    'Should reject conversations of deleted groups'
);

-- Should reject conversations of other users
select throws_ok(
    format($$select add_inbox_user_message(%L::uuid, %L::uuid, 'Hello')$$, :'userID', :'conversationOtherUserID'),
    'OCG01',
    'conversation not found',
    'Should reject conversations of other users'
);

-- Should reject conversations marked as spam
select throws_ok(
    format($$select add_inbox_user_message(%L::uuid, %L::uuid, 'Hello')$$, :'userID', :'conversationSpamID'),
    'OCG01',
    'conversation no longer accepts messages',
    'Should reject conversations marked as spam'
);
select results_eq(
    format(
        $$select
            (select count(*) from inbox_message where inbox_conversation_id = %L::uuid),
            (select inbox_conversation_status_id from inbox_conversation where inbox_conversation_id = %L::uuid)$$,
        :'conversationSpamID',
        :'conversationSpamID'
    ),
    $$values (0::bigint, 'spam')$$,
    'Should keep conversations marked as spam unchanged'
);

-- Should reject users who reached the daily message limit
select throws_ok(
    format($$select add_inbox_user_message(%L::uuid, %L::uuid, 'Hello')$$, :'limitedUserID', :'conversationLimitedID'),
    'OCG01',
    'daily message limit reached',
    'Should reject users who reached the daily message limit'
);

-- Should send the last follow-up allowed by the daily limit
select lives_ok(
    format($$select add_inbox_user_message(%L::uuid, %L::uuid, 'Hello')$$, :'nearLimitUserID', :'conversationNearLimitID'),
    'Should send the last follow-up allowed by the daily limit'
);

-- Send a follow-up to the answered conversation
select add_inbox_user_message(:'userID'::uuid, :'conversationAnsweredID'::uuid, ' Thanks! ')::jsonb as "sent" \gset

-- Should open an answered conversation and move its activity time to the message
select results_eq(
    format(
        $$select ic.inbox_conversation_status_id, ic.last_message_at = m.created_at
        from inbox_conversation ic
        join inbox_message m using (inbox_conversation_id)
        where ic.inbox_conversation_id = %L::uuid
        and m.inbox_message_id = %L::uuid$$,
        :'conversationAnsweredID',
        (:'sent'::jsonb)->>'inbox_message_id'
    ),
    $$values ('open', true)$$,
    'Should open an answered conversation and move its activity time to the message'
);

-- Should store the trimmed follow-up and return its identifiers
select results_eq(
    format(
        $$select m.author_user_id, m.body, ic.group_id, m.kind
        from inbox_message m
        join inbox_conversation ic using (inbox_conversation_id)
        where m.inbox_message_id = %L::uuid
        and ic.inbox_conversation_id = %L::uuid
        and ic.group_id = %L::uuid$$,
        (:'sent'::jsonb)->>'inbox_message_id',
        (:'sent'::jsonb)->>'inbox_conversation_id',
        (:'sent'::jsonb)->>'group_id'
    ),
    format($$values (%L::uuid, 'Thanks!', %L::uuid, 'user-reply')$$, :'userID', :'groupID'),
    'Should store the trimmed follow-up and return its identifiers'
);

-- Should record only the message audit row at the message time for a conversation that was not closed
select results_eq(
    format(
        $$select action, actor_user_id, community_id, details, event_id, group_id, resource_type,
            created_at = (select max(m.created_at) from inbox_message m where m.inbox_conversation_id = resource_id)
        from audit_log
        where resource_id = %L::uuid$$,
        :'conversationAnsweredID'
    ),
    format(
        $$values ('inbox_message_sent', %L::uuid, %L::uuid, '{}'::jsonb, %L::uuid, %L::uuid, 'inbox_conversation', true)$$,
        :'userID',
        :'communityID',
        :'eventID',
        :'groupID'
    ),
    'Should record only the message audit row at the message time for a conversation that was not closed'
);

-- Should send a follow-up to a closed conversation
select lives_ok(
    format($$select add_inbox_user_message(%L::uuid, %L::uuid, 'One more thing')$$, :'userID', :'conversationClosedID'),
    'Should send a follow-up to a closed conversation'
);

-- Should reopen a closed conversation
select is(
    (select inbox_conversation_status_id from inbox_conversation where inbox_conversation_id = :'conversationClosedID'),
    'open',
    'Should reopen a closed conversation'
);

-- Should record the message and the reopening in the audit log at the message time
select results_eq(
    format(
        $$select action, actor_user_id, community_id, details, event_id, group_id, resource_type,
            created_at = (select max(m.created_at) from inbox_message m where m.inbox_conversation_id = resource_id)
        from audit_log
        where resource_id = %L::uuid
        order by action$$,
        :'conversationClosedID'
    ),
    format(
        $$values
            ('inbox_conversation_reopened', %1$L::uuid, %2$L::uuid, '{}'::jsonb, %3$L::uuid, %4$L::uuid, 'inbox_conversation', true),
            ('inbox_message_sent', %1$L::uuid, %2$L::uuid, '{}'::jsonb, %3$L::uuid, %4$L::uuid, 'inbox_conversation', true)$$,
        :'userID',
        :'communityID',
        :'eventID',
        :'groupID'
    ),
    'Should record the message and the reopening in the audit log at the message time'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
