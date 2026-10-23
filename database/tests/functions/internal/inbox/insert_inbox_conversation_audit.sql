-- Tests recording audit rows for inbox conversations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'f6a20000-0000-0000-0000-000000000001'
\set communityID 'f6a20000-0000-0000-0000-000000000002'
\set conversationEventID 'f6a20000-0000-0000-0000-000000000003'
\set conversationNoEventID 'f6a20000-0000-0000-0000-000000000004'
\set eventCategoryID 'f6a20000-0000-0000-0000-000000000005'
\set eventID 'f6a20000-0000-0000-0000-000000000006'
\set groupCategoryID 'f6a20000-0000-0000-0000-000000000007'
\set groupID 'f6a20000-0000-0000-0000-000000000008'
\set userID 'f6a20000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Actor recorded by the audit rows
select fx_user(:'actorID', jsonb_build_object('username', 'inbox-conversation-audit-actor'));

-- User who wrote to the group
select fx_user(:'userID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the conversations
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event the conversation started from
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Conversation about the event
insert into inbox_conversation (inbox_conversation_id, group_id, event_id, user_id)
values (:'conversationEventID', :'groupID', :'eventID', :'userID');

-- Conversation without an event
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationNoEventID', :'groupID', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should record the audit row of a conversation about an event
select lives_ok(
    format(
        $$select insert_inbox_conversation_audit('inbox_message_sent', %L::uuid, ic, '2030-01-10 10:00:00+00') from inbox_conversation ic where ic.inbox_conversation_id = %L::uuid$$,
        :'actorID',
        :'conversationEventID'
    ),
    'Should accept recording the audit row of a conversation about an event'
);
select results_eq(
    format(
        $$select action, actor_user_id, actor_username, community_id, created_at, details, event_id, group_id, resource_type
        from audit_log
        where resource_id = %L::uuid$$,
        :'conversationEventID'
    ),
    format(
        $$values (
            'inbox_message_sent',
            %L::uuid,
            'inbox-conversation-audit-actor',
            %L::uuid,
            '2030-01-10 10:00:00+00'::timestamptz,
            '{}'::jsonb,
            %L::uuid,
            %L::uuid,
            'inbox_conversation'
        )$$,
        :'actorID',
        :'communityID',
        :'eventID',
        :'groupID'
    ),
    'Should record the audit row of a conversation about an event'
);

-- Should record the audit row of a conversation without an event
select lives_ok(
    format(
        $$select insert_inbox_conversation_audit('inbox_conversation_closed', %L::uuid, ic, '2030-01-11 10:00:00+00') from inbox_conversation ic where ic.inbox_conversation_id = %L::uuid$$,
        :'actorID',
        :'conversationNoEventID'
    ),
    'Should accept recording the audit row of a conversation without an event'
);
select results_eq(
    format(
        $$select action, actor_user_id, actor_username, community_id, created_at, details, event_id, group_id, resource_type
        from audit_log
        where resource_id = %L::uuid$$,
        :'conversationNoEventID'
    ),
    format(
        $$values (
            'inbox_conversation_closed',
            %L::uuid,
            'inbox-conversation-audit-actor',
            %L::uuid,
            '2030-01-11 10:00:00+00'::timestamptz,
            '{}'::jsonb,
            null::uuid,
            %L::uuid,
            'inbox_conversation'
        )$$,
        :'actorID',
        :'communityID',
        :'groupID'
    ),
    'Should record the audit row of a conversation without an event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
