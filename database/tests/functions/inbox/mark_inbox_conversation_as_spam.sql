-- Tests marking inbox conversations as spam.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '1b170000-0000-0000-0000-000000000001'
\set communityID '1b170000-0000-0000-0000-000000000002'
\set conversationClosedID '1b170000-0000-0000-0000-000000000003'
\set conversationOpenID '1b170000-0000-0000-0000-000000000004'
\set conversationOtherGroupID '1b170000-0000-0000-0000-000000000005'
\set conversationSpamID '1b170000-0000-0000-0000-000000000006'
\set eventCategoryID '1b170000-0000-0000-0000-000000000007'
\set eventID '1b170000-0000-0000-0000-000000000008'
\set groupCategoryID '1b170000-0000-0000-0000-000000000009'
\set groupID '1b170000-0000-0000-0000-000000000010'
\set otherGroupID '1b170000-0000-0000-0000-000000000011'
\set userID '1b170000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Actor marking conversations on behalf of the group
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

-- Event the open conversation started from
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Closed conversation
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, user_id)
values (:'conversationClosedID', :'groupID', 'closed', :'userID');

-- Open conversation of the user
insert into inbox_conversation (inbox_conversation_id, group_id, last_message_at, event_id, user_id)
values (:'conversationOpenID', :'groupID', '2020-01-10 10:00:00+00', :'eventID', :'userID');

-- Conversation of another group
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationOtherGroupID', :'otherGroupID', :'userID');

-- Conversation already marked as spam
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, user_id)
values (:'conversationSpamID', :'groupID', 'spam', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep a conversation already marked as spam unchanged without an audit row
select lives_ok(
    format($$select mark_inbox_conversation_as_spam(%L::uuid, %L::uuid, %L::uuid)$$, :'actorID', :'groupID', :'conversationSpamID'),
    'Should accept marking a conversation already marked as spam'
);
select is_empty(
    format($$select 1 from audit_log where resource_id = %L::uuid$$, :'conversationSpamID'),
    'Should keep a conversation already marked as spam unchanged without an audit row'
);

-- Should mark a closed conversation as spam
select lives_ok(
    format($$select mark_inbox_conversation_as_spam(%L::uuid, %L::uuid, %L::uuid)$$, :'actorID', :'groupID', :'conversationClosedID'),
    'Should mark a closed conversation as spam'
);
select is(
    (select inbox_conversation_status_id from inbox_conversation where inbox_conversation_id = :'conversationClosedID'),
    'spam',
    'Should store the spam status of a closed conversation'
);

-- Should mark an open conversation as spam without changing its activity time
select lives_ok(
    format($$select mark_inbox_conversation_as_spam(%L::uuid, %L::uuid, %L::uuid)$$, :'actorID', :'groupID', :'conversationOpenID'),
    'Should mark an open conversation as spam'
);
select results_eq(
    format(
        $$select inbox_conversation_status_id, last_message_at from inbox_conversation where inbox_conversation_id = %L::uuid$$,
        :'conversationOpenID'
    ),
    $$values ('spam', '2020-01-10 10:00:00+00'::timestamptz)$$,
    'Should mark an open conversation as spam without changing its activity time'
);

-- Check the audit row uses the post-lock write time instead of the transaction start
select results_eq(
    format(
        $$select action, actor_user_id, community_id, details, event_id, group_id, resource_type,
            created_at > now()
        from audit_log
        where resource_id = %L::uuid$$,
        :'conversationOpenID'
    ),
    format(
        $$values ('inbox_conversation_marked_as_spam', %L::uuid, %L::uuid, '{}'::jsonb, %L::uuid, %L::uuid, 'inbox_conversation', true)$$,
        :'actorID',
        :'communityID',
        :'eventID',
        :'groupID'
    ),
    'Should record the spam mark in the audit log at the write time'
);

-- Should reject conversations of other groups
select throws_ok(
    format($$select mark_inbox_conversation_as_spam(%L::uuid, %L::uuid, %L::uuid)$$, :'actorID', :'groupID', :'conversationOtherGroupID'),
    'OCG01',
    'conversation not found',
    'Should reject conversations of other groups'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
