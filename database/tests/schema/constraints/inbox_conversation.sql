-- Tests inbox conversation constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c0030000-0000-0000-0000-000000000001'
\set conversationEventID 'c0030000-0000-0000-0000-000000000002'
\set conversationUserID 'c0030000-0000-0000-0000-000000000003'
\set crossGroupEventID 'c0030000-0000-0000-0000-000000000004'
\set eventCategoryID 'c0030000-0000-0000-0000-000000000005'
\set eventID 'c0030000-0000-0000-0000-000000000006'
\set groupCategoryID 'c0030000-0000-0000-0000-000000000007'
\set groupID 'c0030000-0000-0000-0000-000000000008'
\set otherGroupID 'c0030000-0000-0000-0000-000000000009'
\set userID 'c0030000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- User deleted by the user deletion scenario
select fx_user(:'userID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the conversations
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group used by the cross-group event scenario
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Event referenced by the cross-group event scenario
select fx_event(:'crossGroupEventID', :'groupID', :'eventCategoryID');

-- Event deleted by the event deletion scenario
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Conversation that references the deleted event
insert into inbox_conversation (inbox_conversation_id, group_id, event_id)
values (:'conversationEventID', :'groupID', :'eventID');

-- Conversation started by the deleted user
insert into inbox_conversation (inbox_conversation_id, group_id, user_id)
values (:'conversationUserID', :'groupID', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep a conversation and clear its event when the event is deleted
select lives_ok(
    format($$delete from event where event_id = %L::uuid$$, :'eventID'),
    'Should delete an event referenced by a conversation'
);
select results_eq(
    format(
        $$select event_id, group_id from inbox_conversation where inbox_conversation_id = %L::uuid$$,
        :'conversationEventID'
    ),
    format($$values (null::uuid, %L::uuid)$$, :'groupID'),
    'Should keep a conversation and clear its event when the event is deleted'
);

-- Should keep a conversation and clear its user when the user is deleted
select lives_ok(
    format($$delete from "user" where user_id = %L::uuid$$, :'userID'),
    'Should delete a user referenced by a conversation'
);
select results_eq(
    format(
        $$select group_id, user_id from inbox_conversation where inbox_conversation_id = %L::uuid$$,
        :'conversationUserID'
    ),
    format($$values (%L::uuid, null::uuid)$$, :'groupID'),
    'Should keep a conversation and clear its user when the user is deleted'
);

-- Should reject a conversation event owned by another group
select throws_ok(
    format(
        $$insert into inbox_conversation (group_id, event_id) values (%L::uuid, %L::uuid)$$,
        :'otherGroupID',
        :'crossGroupEventID'
    ),
    '23503',
    null,
    'Should reject a conversation event owned by another group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
