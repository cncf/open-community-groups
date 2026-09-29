-- Tests starting inbox conversations from the event page.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID '1b090000-0000-0000-0000-000000000001'
\set communityID '1b090000-0000-0000-0000-000000000002'
\set conflictConversationID '1b090000-0000-0000-0000-000000000003'
\set conflictUserID '1b090000-0000-0000-0000-000000000004'
\set eventCategoryID '1b090000-0000-0000-0000-000000000005'
\set eventID '1b090000-0000-0000-0000-000000000006'
\set groupCategoryID '1b090000-0000-0000-0000-000000000007'
\set groupID '1b090000-0000-0000-0000-000000000008'
\set limitedUserID '1b090000-0000-0000-0000-000000000009'
\set nearLimitUserID '1b090000-0000-0000-0000-000000000010'
\set otherGroupID '1b090000-0000-0000-0000-000000000012'
\set spamConversationID '1b090000-0000-0000-0000-000000000015'
\set spamUserID '1b090000-0000-0000-0000-000000000016'
\set teamMemberID '1b090000-0000-0000-0000-000000000011'
\set unpublishedEventID '1b090000-0000-0000-0000-000000000013'
\set userID '1b090000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- User with an open conversation with the group
select fx_user(:'conflictUserID');

-- User who reached the daily limit of new conversations
select fx_user(:'limitedUserID');

-- User one conversation below the daily limit
select fx_user(:'nearLimitUserID');

-- User whose conversation the group marked as spam
select fx_user(:'spamUserID');

-- Accepted team member of the group owning the event
select fx_user(:'teamMemberID');

-- User starting a conversation
select fx_user(:'userID', jsonb_build_object('username', 'inbox-start-user'));

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group co-hosting the event
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');

-- Group contacted earlier by the limited users
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Published event co-hosted by another group
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Unpublished event
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID');

-- Approved co-host of the event
insert into event_cohost (event_id, group_id, event_cohost_status_id, approved_at)
values (:'eventID', :'cohostGroupID', 'approved', current_timestamp);

-- Accepted events-manager membership of the team member
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'events-manager', :'teamMemberID');

-- Open conversation of the conflict user with the group
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conflictConversationID', :'groupID', :'conflictUserID');

-- Conversations started today by the limited user
insert into inbox_conversation (created_at, group_id, inbox_conversation_status_id, user_id) values
    (current_timestamp - interval '3 hours', :'otherGroupID', 'answered', :'limitedUserID'),
    (current_timestamp - interval '2 hours', :'otherGroupID', 'answered', :'limitedUserID'),
    (current_timestamp - interval '1 hour', :'otherGroupID', 'answered', :'limitedUserID');

-- Conversations started today by the user below the limit
insert into inbox_conversation (created_at, group_id, inbox_conversation_status_id, user_id) values
    (current_timestamp - interval '2 hours', :'otherGroupID', 'answered', :'nearLimitUserID'),
    (current_timestamp - interval '1 hour', :'otherGroupID', 'answered', :'nearLimitUserID');

-- Conversation of the spam user marked as spam by the group
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, inbox_conversation_status_id, user_id)
values (:'spamConversationID', current_timestamp - interval '2 days', :'groupID', 'spam', :'spamUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should point users with an open conversation to it without writing rows
select is(
    start_inbox_conversation(:'conflictUserID'::uuid, :'communityID'::uuid, :'eventID'::uuid, 'Hello again')::jsonb,
    '{"conflict": "open-conversation"}'::jsonb,
    'Should point users with an open conversation to it'
);
select is(
    (
        select count(*)::int
        from inbox_conversation ic
        left join inbox_message m using (inbox_conversation_id)
        where ic.user_id = :'conflictUserID'
    ),
    1,
    'Should not write rows when pointing users to an open conversation'
);

-- Should reject events that do not accept contact
select throws_ok(
    format($$select start_inbox_conversation(%L::uuid, %L::uuid, %L::uuid, 'Hello')$$, :'userID', :'communityID', :'unpublishedEventID'),
    'OCG01',
    'event not found',
    'Should reject events that do not accept contact'
);

-- Should reject group team members contacting their own group
select throws_ok(
    format($$select start_inbox_conversation(%L::uuid, %L::uuid, %L::uuid, 'Hello')$$, :'teamMemberID', :'communityID', :'eventID'),
    'OCG01',
    'group team members cannot contact their own group',
    'Should reject group team members contacting their own group'
);

-- Should reject users blocked by spam reports without writing rows
select throws_ok(
    format($$select start_inbox_conversation(%L::uuid, %L::uuid, %L::uuid, 'Hello')$$, :'spamUserID', :'communityID', :'eventID'),
    'OCG01',
    'you can no longer contact this group',
    'Should reject users blocked by spam reports'
);
select is(
    (select count(*)::int from inbox_conversation where user_id = :'spamUserID'),
    1,
    'Should not write rows when rejecting users blocked by spam reports'
);

-- Should reject users who reached the daily limit of new conversations
select throws_ok(
    format($$select start_inbox_conversation(%L::uuid, %L::uuid, %L::uuid, 'Hello')$$, :'limitedUserID', :'communityID', :'eventID'),
    'OCG01',
    'daily limit of new conversations reached',
    'Should reject users who reached the daily limit of new conversations'
);

-- Should start the last conversation allowed by the daily limit
select ok(
    start_inbox_conversation(:'nearLimitUserID'::uuid, :'communityID'::uuid, :'eventID'::uuid, 'Hello')::jsonb ? 'inbox_conversation_id',
    'Should start the last conversation allowed by the daily limit'
);

-- Start a conversation about the co-hosted event
select start_inbox_conversation(
    :'userID'::uuid,
    :'communityID'::uuid,
    :'eventID'::uuid,
    E'  Is there parking nearby?\n'
)::jsonb as "started" \gset

-- Should route a co-hosted event to its owning group
select is(
    (:'started'::jsonb)->>'group_id',
    :'groupID',
    'Should route a co-hosted event to its owning group'
);

-- Should store an open conversation whose creation and activity times match
select results_eq(
    format(
        $$select event_id, group_id, inbox_conversation_status_id, user_id, created_at = last_message_at
        from inbox_conversation
        where inbox_conversation_id = %L::uuid$$,
        (:'started'::jsonb)->>'inbox_conversation_id'
    ),
    format($$values (%L::uuid, %L::uuid, 'open', %L::uuid, true)$$, :'eventID', :'groupID', :'userID'),
    'Should store an open conversation whose creation and activity times match'
);

-- Should store the trimmed first message at the conversation creation time
select results_eq(
    format(
        $$select m.author_user_id, m.body, m.kind, m.created_at = ic.created_at
        from inbox_message m
        join inbox_conversation ic using (inbox_conversation_id)
        where m.inbox_message_id = %L::uuid
        and m.inbox_conversation_id = %L::uuid$$,
        (:'started'::jsonb)->>'inbox_message_id',
        (:'started'::jsonb)->>'inbox_conversation_id'
    ),
    format($$values (%L::uuid, 'Is there parking nearby?', 'initial', true)$$, :'userID'),
    'Should store the trimmed first message at the conversation creation time'
);

-- Should record the conversation start in the audit log at the message time
select results_eq(
    format(
        $$select action, actor_user_id, community_id, details, event_id, group_id, resource_id, resource_type,
            created_at = (select max(m.created_at) from inbox_message m where m.inbox_conversation_id = resource_id)
        from audit_log
        where resource_id = %L::uuid$$,
        (:'started'::jsonb)->>'inbox_conversation_id'
    ),
    format(
        $$values ('inbox_conversation_started', %L::uuid, %L::uuid, '{}'::jsonb, %L::uuid, %L::uuid, %L::uuid, 'inbox_conversation', true)$$,
        :'userID',
        :'communityID',
        :'eventID',
        :'groupID',
        (:'started'::jsonb)->>'inbox_conversation_id'
    ),
    'Should record the conversation start in the audit log at the message time'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
