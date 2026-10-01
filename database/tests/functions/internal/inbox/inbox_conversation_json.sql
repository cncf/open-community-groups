-- Tests projecting inbox conversation threads.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1b060000-0000-0000-0000-000000000001'
\set conversationDeletedEventID '1b060000-0000-0000-0000-000000000002'
\set conversationDeletedUserID '1b060000-0000-0000-0000-000000000003'
\set conversationID '1b060000-0000-0000-0000-000000000004'
\set conversationUnpublishedEventID '1b060000-0000-0000-0000-000000000005'
\set conversationWithoutEventID '1b060000-0000-0000-0000-000000000006'
\set deletedEventID '1b060000-0000-0000-0000-000000000007'
\set eventCategoryID '1b060000-0000-0000-0000-000000000008'
\set eventID '1b060000-0000-0000-0000-000000000009'
\set groupCategoryID '1b060000-0000-0000-0000-000000000010'
\set groupID '1b060000-0000-0000-0000-000000000011'
\set messageFirstID '1b060000-0000-0000-0000-000000000012'
\set messageSameTimeFirstID '1b060000-0000-0000-0000-000000000013'
\set messageSameTimeSecondID '1b060000-0000-0000-0000-000000000014'
\set messageSecondID '1b060000-0000-0000-0000-000000000015'
\set replierID '1b060000-0000-0000-0000-000000000016'
\set unpublishedEventID '1b060000-0000-0000-0000-000000000017'
\set userID '1b060000-0000-0000-0000-000000000018'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID', jsonb_build_object(
    'display_name', 'Inbox Json Community',
    'name', 'inbox-json-community'
));

-- Group team member replying to the user
select fx_user(:'replierID', jsonb_build_object(
    'name', 'Riley Replier',
    'username', 'inbox-json-replier'
));

-- User who started the conversations
select fx_user(:'userID', jsonb_build_object(
    'name', 'Uma User',
    'username', 'inbox-json-user'
));

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group with a pretty slug
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Inbox Json Group',
    'slug', 'inbox-json-group',
    'slug_pretty', 'inbox-json'
));

-- Published event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Inbox Json Event',
    'published', true,
    'slug', 'inbox-json-event'
));

-- Soft-deleted event
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('deleted', true));

-- Unpublished event
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID');

-- Conversation about the published event
insert into inbox_conversation (
    inbox_conversation_id,
    created_at,
    group_id,
    inbox_conversation_status_id,
    last_message_at,

    event_id,
    user_id
) values (
    :'conversationID',
    '2030-01-10 10:00:00+00',
    :'groupID',
    'answered',
    '2030-01-10 11:00:00+00',

    :'eventID',
    :'userID'
);

-- Conversation about the soft-deleted event
insert into inbox_conversation (inbox_conversation_id, group_id, event_id, user_id)
values (:'conversationDeletedEventID', :'groupID', :'deletedEventID', :'userID');

-- Conversation whose user account was deleted
insert into inbox_conversation (inbox_conversation_id, group_id, event_id)
values (:'conversationDeletedUserID', :'groupID', :'eventID');

-- Conversation about the unpublished event
insert into inbox_conversation (inbox_conversation_id, group_id, event_id, user_id)
values (:'conversationUnpublishedEventID', :'groupID', :'unpublishedEventID', :'userID');

-- Conversation whose event row was removed
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationWithoutEventID', :'groupID', :'userID');

-- Messages of the conversation about the published event, stored out of order
insert into inbox_message (inbox_message_id, body, created_at, inbox_conversation_id, kind, author_user_id) values
    (:'messageSecondID', 'Doors open at 6pm.', '2030-01-10 11:00:00+00', :'conversationID', 'group-reply', :'replierID'),
    (:'messageFirstID', 'When do doors open?', '2030-01-10 10:00:00+00', :'conversationID', 'initial', :'userID');

-- Messages sharing a creation time in the conversation of the deleted user
insert into inbox_message (inbox_message_id, body, created_at, inbox_conversation_id, kind, author_user_id) values
    (:'messageSameTimeSecondID', 'Second', '2030-01-10 10:00:00+00', :'conversationDeletedUserID', 'user-reply', null),
    (:'messageSameTimeFirstID', 'First', '2030-01-10 10:00:00+00', :'conversationDeletedUserID', 'initial', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should emit a deleted user and a deleted author as JSON null
select ok(
    inbox_conversation_json(:'conversationDeletedUserID'::uuid)::jsonb @> '{"user": null, "messages": [{"author": null}]}'::jsonb
    and inbox_conversation_json(:'conversationDeletedUserID'::uuid)::jsonb ? 'user',
    'Should emit a deleted user and a deleted author as JSON null'
);

-- Should flag a soft-deleted event as not public
select is(
    inbox_conversation_json(:'conversationDeletedEventID'::uuid)::jsonb->'event'->'is_public',
    'false'::jsonb,
    'Should flag a soft-deleted event as not public'
);

-- Should flag an unpublished event as not public
select is(
    inbox_conversation_json(:'conversationUnpublishedEventID'::uuid)::jsonb->'event'->'is_public',
    'false'::jsonb,
    'Should flag an unpublished event as not public'
);

-- Should omit the event when the conversation no longer references one
select ok(
    not (inbox_conversation_json(:'conversationWithoutEventID'::uuid)::jsonb ? 'event'),
    'Should omit the event when the conversation no longer references one'
);

-- Should order messages sharing a creation time by identifier
select is(
    (
        select jsonb_agg(m->'inbox_message_id')
        from jsonb_array_elements(inbox_conversation_json(:'conversationDeletedUserID'::uuid)::jsonb->'messages') m
    ),
    jsonb_build_array(:'messageSameTimeFirstID'::uuid, :'messageSameTimeSecondID'::uuid),
    'Should order messages sharing a creation time by identifier'
);

-- Should project the full thread in chronological order
select is(
    inbox_conversation_json(:'conversationID'::uuid)::jsonb,
    format('{
        "community_display_name": "Inbox Json Community",
        "community_name": "inbox-json-community",
        "created_at": 1894269600,
        "group_id": "%s",
        "group_name": "Inbox Json Group",
        "group_slug": "inbox-json-group",
        "inbox_conversation_id": "%s",
        "last_message_at": 1894273200,
        "messages": [
            {
                "body": "When do doors open?",
                "created_at": 1894269600,
                "inbox_message_id": "%s",
                "kind": "initial",
                "author": {"name": "Uma User", "user_id": "%s", "username": "inbox-json-user"}
            },
            {
                "body": "Doors open at 6pm.",
                "created_at": 1894273200,
                "inbox_message_id": "%s",
                "kind": "group-reply",
                "author": {"name": "Riley Replier", "user_id": "%s", "username": "inbox-json-replier"}
            }
        ],
        "status": "answered",

        "event": {
            "event_id": "%s",
            "is_public": true,
            "name": "Inbox Json Event",
            "slug": "inbox-json-event"
        },
        "group_slug_pretty": "inbox-json",
        "user": {"name": "Uma User", "user_id": "%s", "username": "inbox-json-user"}
    }',
        :'groupID',
        :'conversationID',
        :'messageFirstID',
        :'userID',
        :'messageSecondID',
        :'replierID',
        :'eventID',
        :'userID'
    )::jsonb,
    'Should project the full thread in chronological order'
);

-- Should return null for an unknown conversation
select is(
    inbox_conversation_json(:'groupID'::uuid)::jsonb,
    null,
    'Should return null for an unknown conversation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
