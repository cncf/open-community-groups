-- Tests adding group replies to inbox conversations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '1b0b0000-0000-0000-0000-000000000009'
\set communityID '1b0b0000-0000-0000-0000-000000000001'
\set conversationClosedID '1b0b0000-0000-0000-0000-000000000002'
\set conversationDeletedUserID '1b0b0000-0000-0000-0000-000000000003'
\set conversationOtherGroupID '1b0b0000-0000-0000-0000-000000000004'
\set conversationSpamID '1b0b0000-0000-0000-0000-000000000012'
\set eventCategoryID '1b0b0000-0000-0000-0000-000000000005'
\set eventID '1b0b0000-0000-0000-0000-000000000006'
\set groupCategoryID '1b0b0000-0000-0000-0000-000000000007'
\set groupID '1b0b0000-0000-0000-0000-000000000008'
\set otherGroupID '1b0b0000-0000-0000-0000-000000000010'
\set userID '1b0b0000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Actor replying on behalf of the group
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

-- Event the conversation started from
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Closed conversation of the user
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, last_message_at, event_id, user_id)
values (:'conversationClosedID', :'groupID', 'closed', '2020-01-10 10:00:00+00', :'eventID', :'userID');

-- Conversation whose user account was deleted
insert into inbox_conversation (inbox_conversation_id, group_id)
values (:'conversationDeletedUserID', :'groupID');

-- Conversation of another group
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationOtherGroupID', :'otherGroupID', :'userID');

-- Conversation marked as spam
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, user_id)
values (:'conversationSpamID', :'groupID', 'spam', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject conversations of other groups
select throws_ok(
    format($$select add_inbox_group_reply(%L::uuid, %L::uuid, %L::uuid, 'Hi')$$, :'actorID', :'groupID', :'conversationOtherGroupID'),
    'OCG01',
    'conversation not found',
    'Should reject conversations of other groups'
);

-- Should reject replies to conversations marked as spam
select throws_ok(
    format($$select add_inbox_group_reply(%L::uuid, %L::uuid, %L::uuid, 'Hi')$$, :'actorID', :'groupID', :'conversationSpamID'),
    'OCG01',
    'conversation is marked as spam',
    'Should reject replies to conversations marked as spam'
);
select is_empty(
    format($$select 1 from inbox_message where inbox_conversation_id = %L::uuid$$, :'conversationSpamID'),
    'Should store no reply in conversations marked as spam'
);

-- Should reject replies to conversations whose user account was deleted
select throws_ok(
    format($$select add_inbox_group_reply(%L::uuid, %L::uuid, %L::uuid, 'Hi')$$, :'actorID', :'groupID', :'conversationDeletedUserID'),
    'OCG01',
    'conversation is read-only',
    'Should reject replies to conversations whose user account was deleted'
);

-- Reply to the closed conversation
select add_inbox_group_reply(
    :'actorID'::uuid,
    :'groupID'::uuid,
    :'conversationClosedID'::uuid,
    E'Yes, see you there.\n'
)::jsonb as "replied" \gset

-- Should answer a closed conversation and move its activity time to the reply
select results_eq(
    format(
        $$select ic.inbox_conversation_status_id, ic.last_message_at = m.created_at
        from inbox_conversation ic
        join inbox_message m using (inbox_conversation_id)
        where ic.inbox_conversation_id = %L::uuid
        and m.inbox_message_id = %L::uuid$$,
        :'conversationClosedID',
        (:'replied'::jsonb)->>'inbox_message_id'
    ),
    $$values ('answered', true)$$,
    'Should answer a closed conversation and move its activity time to the reply'
);

-- Should store the trimmed reply and return its identifiers
select results_eq(
    format(
        $$select m.author_user_id, m.body, ic.group_id, m.kind
        from inbox_message m
        join inbox_conversation ic using (inbox_conversation_id)
        where m.inbox_message_id = %L::uuid
        and ic.inbox_conversation_id = %L::uuid
        and ic.group_id = %L::uuid$$,
        (:'replied'::jsonb)->>'inbox_message_id',
        (:'replied'::jsonb)->>'inbox_conversation_id',
        (:'replied'::jsonb)->>'group_id'
    ),
    format($$values (%L::uuid, 'Yes, see you there.', %L::uuid, 'group-reply')$$, :'actorID', :'groupID'),
    'Should store the trimmed reply and return its identifiers'
);

-- Should record the reply in the audit log at the message time
select results_eq(
    format(
        $$select action, actor_user_id, community_id, details, event_id, group_id, resource_type,
            created_at = (select max(m.created_at) from inbox_message m where m.inbox_conversation_id = resource_id)
        from audit_log
        where resource_id = %L::uuid$$,
        :'conversationClosedID'
    ),
    format(
        $$values ('inbox_reply_sent', %L::uuid, %L::uuid, '{}'::jsonb, %L::uuid, %L::uuid, 'inbox_conversation', true)$$,
        :'actorID',
        :'communityID',
        :'eventID',
        :'groupID'
    ),
    'Should record the reply in the audit log at the message time'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
