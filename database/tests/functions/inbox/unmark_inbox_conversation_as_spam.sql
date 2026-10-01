-- Tests unmarking inbox conversations as spam.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '1b180000-0000-0000-0000-000000000001'
\set communityID '1b180000-0000-0000-0000-000000000002'
\set conversationClosedID '1b180000-0000-0000-0000-000000000003'
\set conversationOtherGroupID '1b180000-0000-0000-0000-000000000004'
\set conversationSpamAnsweredID '1b180000-0000-0000-0000-000000000005'
\set conversationSpamOpenID '1b180000-0000-0000-0000-000000000006'
\set eventCategoryID '1b180000-0000-0000-0000-000000000007'
\set eventID '1b180000-0000-0000-0000-000000000008'
\set groupCategoryID '1b180000-0000-0000-0000-000000000009'
\set groupID '1b180000-0000-0000-0000-000000000010'
\set otherGroupID '1b180000-0000-0000-0000-000000000011'
\set userID '1b180000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Actor unmarking conversations on behalf of the group
select fx_user(:'actorID');

-- User who wrote to the group
select fx_user(:'userID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the conversations
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Another group
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Event the conversation whose user wrote last started from
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Closed conversation
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, user_id)
values (:'conversationClosedID', :'groupID', 'closed', :'userID');

-- Spam conversation of another group
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, user_id)
values (:'conversationOtherGroupID', :'otherGroupID', 'spam', :'userID');

-- Spam conversation whose group wrote last
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'conversationSpamAnsweredID', :'groupID', 'spam', '2020-01-10 11:00:00+00', :'userID');

-- Spam conversation whose user wrote last
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, last_message_at, event_id, user_id)
values (:'conversationSpamOpenID', :'groupID', 'spam', '2020-01-10 12:00:00+00', :'eventID', :'userID');

-- Messages of the spam conversation whose group wrote last
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id) values
    ('Question', '2020-01-10 10:00:00+00', :'conversationSpamAnsweredID', 'initial', :'userID'),
    ('Reply', '2020-01-10 11:00:00+00', :'conversationSpamAnsweredID', 'group-reply', :'actorID');

-- Messages of the spam conversation whose user wrote last
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id) values
    ('Question', '2020-01-10 10:00:00+00', :'conversationSpamOpenID', 'initial', :'userID'),
    ('Reply', '2020-01-10 11:00:00+00', :'conversationSpamOpenID', 'group-reply', :'actorID'),
    ('Follow-up', '2020-01-10 12:00:00+00', :'conversationSpamOpenID', 'user-reply', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep a conversation not marked as spam unchanged without an audit row
select lives_ok(
    format($$select unmark_inbox_conversation_as_spam(%L::uuid, %L::uuid, %L::uuid)$$, :'actorID', :'groupID', :'conversationClosedID'),
    'Should accept unmarking a conversation not marked as spam'
);
select is(
    (select inbox_conversation_status_id from inbox_conversation where inbox_conversation_id = :'conversationClosedID'),
    'closed',
    'Should keep the status of a conversation not marked as spam'
);
select is_empty(
    format($$select 1 from audit_log where resource_id = %L::uuid$$, :'conversationClosedID'),
    'Should keep a conversation not marked as spam unchanged without an audit row'
);

-- Should reject conversations of other groups
select throws_ok(
    format($$select unmark_inbox_conversation_as_spam(%L::uuid, %L::uuid, %L::uuid)$$, :'actorID', :'groupID', :'conversationOtherGroupID'),
    'OCG01',
    'conversation not found',
    'Should reject conversations of other groups'
);

-- Should restore the answered status when the group wrote last
select lives_ok(
    format($$select unmark_inbox_conversation_as_spam(%L::uuid, %L::uuid, %L::uuid)$$, :'actorID', :'groupID', :'conversationSpamAnsweredID'),
    'Should unmark a conversation whose group wrote last'
);
select results_eq(
    format(
        $$select inbox_conversation_status_id, last_message_at from inbox_conversation where inbox_conversation_id = %L::uuid$$,
        :'conversationSpamAnsweredID'
    ),
    $$values ('answered', '2020-01-10 11:00:00+00'::timestamptz)$$,
    'Should restore the answered status when the group wrote last'
);

-- Should restore the open status when the user wrote last
select lives_ok(
    format($$select unmark_inbox_conversation_as_spam(%L::uuid, %L::uuid, %L::uuid)$$, :'actorID', :'groupID', :'conversationSpamOpenID'),
    'Should unmark a conversation whose user wrote last'
);
select results_eq(
    format(
        $$select inbox_conversation_status_id, last_message_at from inbox_conversation where inbox_conversation_id = %L::uuid$$,
        :'conversationSpamOpenID'
    ),
    $$values ('open', '2020-01-10 12:00:00+00'::timestamptz)$$,
    'Should restore the open status when the user wrote last'
);
select is(
    is_inbox_user_blocked(:'groupID'::uuid, :'userID'::uuid),
    false,
    'Should lift the block of the group once its spam marks are removed'
);

-- Check the audit row uses the post-lock write time instead of the transaction start
select results_eq(
    format(
        $$select action, actor_user_id, community_id, details, event_id, group_id, resource_type,
            created_at > now()
        from audit_log
        where resource_id = %L::uuid$$,
        :'conversationSpamOpenID'
    ),
    format(
        $$values ('inbox_conversation_unmarked_as_spam', %L::uuid, %L::uuid, '{}'::jsonb, %L::uuid, %L::uuid, 'inbox_conversation', true)$$,
        :'actorID',
        :'communityID',
        :'eventID',
        :'groupID'
    ),
    'Should record the spam unmark in the audit log at the write time'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
