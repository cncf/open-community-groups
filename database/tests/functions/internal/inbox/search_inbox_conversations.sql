-- Tests searching inbox conversations by group or user scope.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1b070000-0000-0000-0000-000000000001'
\set conversationAnsweredID '1b070000-0000-0000-0000-000000000002'
\set conversationClosedID '1b070000-0000-0000-0000-000000000003'
\set conversationDeletedGroupID '1b070000-0000-0000-0000-000000000004'
\set conversationOpenID '1b070000-0000-0000-0000-000000000005'
\set conversationOtherGroupID '1b070000-0000-0000-0000-000000000006'
\set conversationSpamID '1b070000-0000-0000-0000-000000000015'
\set deletedGroupID '1b070000-0000-0000-0000-000000000007'
\set eventCategoryID '1b070000-0000-0000-0000-000000000008'
\set eventID '1b070000-0000-0000-0000-000000000009'
\set groupCategoryID '1b070000-0000-0000-0000-000000000010'
\set groupID '1b070000-0000-0000-0000-000000000011'
\set otherGroupID '1b070000-0000-0000-0000-000000000012'
\set otherUserID '1b070000-0000-0000-0000-000000000013'
\set unpublishedEventID '1b070000-0000-0000-0000-000000000016'
\set userID '1b070000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID', jsonb_build_object(
    'display_name', 'Inbox Search Community',
    'name', 'inbox-search-community'
));

-- User writing to several groups
select fx_user(:'userID', jsonb_build_object(
    'name', 'Sam Searcher',
    'username', 'inbox-search-user'
));

-- Another user writing to the group
select fx_user(:'otherUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group whose inbox is listed
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Inbox Search Group'));

-- Another group contacted by the user
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Deleted group contacted by the user
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Published event the user asked about
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Inbox Search Event',
    'published', true
));

-- Unpublished event of another group the user asked about
select fx_event(:'unpublishedEventID', :'otherGroupID', :'eventCategoryID', jsonb_build_object('published', false));

-- Answered conversation of another user
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'conversationAnsweredID', '2030-01-10 10:30:00+00', :'groupID', 'answered', '2030-01-10 11:00:00+00', :'otherUserID');

-- Closed conversation whose user account was deleted
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at)
values (:'conversationClosedID', '2030-01-10 11:00:00+00', :'groupID', 'closed', '2030-01-10 11:00:00+00');

-- Open conversation of the user in a deleted group
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'conversationDeletedGroupID', '2030-01-10 13:00:00+00', :'deletedGroupID', 'open', '2030-01-10 13:00:00+00', :'userID');

-- Open conversation of the user about the event
insert into inbox_conversation (
    inbox_conversation_id,
    created_at,
    group_id,
    inbox_conversation_status_id,
    last_message_at,

    event_id,
    user_id
) values (
    :'conversationOpenID',
    '2030-01-10 10:00:00+00',
    :'groupID',
    'open',
    '2030-01-10 12:00:00+00',

    :'eventID',
    :'userID'
);

-- Open conversation of the user with another group about its unpublished event
insert into inbox_conversation (
    inbox_conversation_id,
    created_at,
    group_id,
    inbox_conversation_status_id,
    last_message_at,

    event_id,
    user_id
) values (
    :'conversationOtherGroupID',
    '2030-01-10 09:00:00+00',
    :'otherGroupID',
    'open',
    '2030-01-10 09:00:00+00',

    :'unpublishedEventID',
    :'userID'
);

-- Conversation of the user marked as spam, with the latest activity in the group
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, last_message_at, user_id)
values (:'conversationSpamID', '2030-01-10 14:00:00+00', :'groupID', 'spam', '2030-01-10 14:00:00+00', :'userID');

-- Messages of the answered conversation
insert into inbox_message (body, created_at, inbox_conversation_id, kind) values
    ('Question', '2030-01-10 10:30:00+00', :'conversationAnsweredID', 'initial'),
    ('Reply', '2030-01-10 11:00:00+00', :'conversationAnsweredID', 'group-reply');

-- Message of the closed conversation
insert into inbox_message (body, created_at, inbox_conversation_id, kind)
values ('Bye', '2030-01-10 11:00:00+00', :'conversationClosedID', 'initial');

-- Message of the conversation in the deleted group
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id)
values ('Hidden', '2030-01-10 13:00:00+00', :'conversationDeletedGroupID', 'initial', :'userID');

-- Messages of the open conversation, the latest one longer than the excerpt
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id) values
    ('Hello', '2030-01-10 10:00:00+00', :'conversationOpenID', 'initial', :'userID'),
    (repeat('x', 200), '2030-01-10 12:00:00+00', :'conversationOpenID', 'user-reply', :'userID');

-- Message of the conversation with another group
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id)
values ('Other', '2030-01-10 09:00:00+00', :'conversationOtherGroupID', 'initial', :'userID');

-- Message of the conversation marked as spam
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id)
values ('Buy now', '2030-01-10 14:00:00+00', :'conversationSpamID', 'initial', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should emit a deleted user as JSON null
select is(
    search_inbox_conversations(:'groupID'::uuid, null, '{}'::jsonb)::jsonb->'conversations'->1->'user',
    'null'::jsonb,
    'Should emit a deleted user as JSON null'
);

-- Should filter conversations by status
select is(
    (
        select jsonb_build_object(
            'ids', jsonb_path_query_array(r, '$.conversations[*].inbox_conversation_id'),
            'total', r->'total'
        )
        from (select search_inbox_conversations(:'groupID'::uuid, null, '{"status": "open"}'::jsonb)::jsonb as r) t
    ),
    jsonb_build_object('ids', jsonb_build_array(:'conversationOpenID'::uuid), 'total', 1),
    'Should filter conversations by status'
);

-- Should flag an unpublished event as not public
select is(
    search_inbox_conversations(null, :'userID'::uuid, '{}'::jsonb)::jsonb->'conversations'->2->'event',
    jsonb_build_object('event_id', :'unpublishedEventID'::uuid, 'is_public', false, 'name', 'Fixture Event'),
    'Should flag an unpublished event as not public'
);

-- Should list group conversations marked as spam when filtered by them
select is(
    (
        select jsonb_build_object(
            'ids', jsonb_path_query_array(r, '$.conversations[*].inbox_conversation_id'),
            'total', r->'total'
        )
        from (select search_inbox_conversations(:'groupID'::uuid, null, '{"status": "spam"}'::jsonb)::jsonb as r) t
    ),
    jsonb_build_object('ids', jsonb_build_array(:'conversationSpamID'::uuid), 'total', 1),
    'Should list group conversations marked as spam when filtered by them'
);

-- Should list group conversations by latest activity leaving spam out
select is(
    (
        select jsonb_build_object(
            'ids', jsonb_path_query_array(r, '$.conversations[*].inbox_conversation_id'),
            'total', r->'total'
        )
        from (select search_inbox_conversations(:'groupID'::uuid, null, '{}'::jsonb)::jsonb as r) t
    ),
    jsonb_build_object(
        'ids', jsonb_build_array(:'conversationOpenID'::uuid, :'conversationClosedID'::uuid, :'conversationAnsweredID'::uuid),
        'total', 3
    ),
    'Should list group conversations by latest activity leaving spam out'
);

-- Should list user conversations including spam and excluding deleted groups
select is(
    (
        select jsonb_build_object(
            'ids', jsonb_path_query_array(r, '$.conversations[*].inbox_conversation_id'),
            'total', r->'total'
        )
        from (select search_inbox_conversations(null, :'userID'::uuid, '{}'::jsonb)::jsonb as r) t
    ),
    jsonb_build_object(
        'ids', jsonb_build_array(:'conversationSpamID'::uuid, :'conversationOpenID'::uuid, :'conversationOtherGroupID'::uuid),
        'total', 3
    ),
    'Should list user conversations including spam and excluding deleted groups'
);

-- Should paginate conversations and keep the total
select is(
    (
        select jsonb_build_object(
            'ids', jsonb_path_query_array(r, '$.conversations[*].inbox_conversation_id'),
            'total', r->'total'
        )
        from (select search_inbox_conversations(:'groupID'::uuid, null, '{"limit": 1, "offset": 1}'::jsonb)::jsonb as r) t
    ),
    jsonb_build_object('ids', jsonb_build_array(:'conversationClosedID'::uuid), 'total', 3),
    'Should paginate conversations and keep the total'
);

-- Should project a row with its latest message, event and user
select is(
    search_inbox_conversations(:'groupID'::uuid, null, '{}'::jsonb)::jsonb->'conversations'->0,
    format('{
        "community_display_name": "Inbox Search Community",
        "community_name": "inbox-search-community",
        "created_at": 1894269600,
        "group_id": "%s",
        "group_name": "Inbox Search Group",
        "inbox_conversation_id": "%s",
        "last_message_at": 1894276800,
        "last_message_excerpt": "%s",
        "last_message_kind": "user-reply",
        "status": "open",

        "event": {"event_id": "%s", "is_public": true, "name": "Inbox Search Event"},
        "user": {"name": "Sam Searcher", "user_id": "%s", "username": "inbox-search-user"}
    }', :'groupID', :'conversationOpenID', repeat('x', 160), :'eventID', :'userID')::jsonb,
    'Should project a row with its latest message, event and user'
);

-- Should reject a request with both scopes
select throws_ok(
    format($$select search_inbox_conversations(%L::uuid, %L::uuid, '{}'::jsonb)$$, :'groupID', :'userID'),
    'P0001',
    'exactly one inbox scope is required',
    'Should reject a request with both scopes'
);

-- Should reject a request without scope
select throws_ok(
    $$select search_inbox_conversations(null, null, '{}'::jsonb)$$,
    'P0001',
    'exactly one inbox scope is required',
    'Should reject a request without scope'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
