-- Tests the rolling daily inbox limits of a user.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1b040000-0000-0000-0000-000000000001'
\set conversationBoundaryID '1b040000-0000-0000-0000-000000000002'
\set conversationLimitedFirstID '1b040000-0000-0000-0000-000000000003'
\set conversationLimitedSecondID '1b040000-0000-0000-0000-000000000004'
\set conversationLimitedThirdID '1b040000-0000-0000-0000-000000000005'
\set conversationOldID '1b040000-0000-0000-0000-000000000006'
\set conversationRecentFirstID '1b040000-0000-0000-0000-000000000007'
\set conversationRecentSecondID '1b040000-0000-0000-0000-000000000008'
\set groupCategoryID '1b040000-0000-0000-0000-000000000009'
\set groupID '1b040000-0000-0000-0000-000000000010'
\set limitedUserID '1b040000-0000-0000-0000-000000000011'
\set userID '1b040000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- User one step below both limits
select fx_user(:'userID');

-- User who reached both limits
select fx_user(:'limitedUserID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group contacted by the users
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Conversations started inside the window by the user below the limits
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, user_id) values
    (:'conversationRecentFirstID', '2030-01-10 01:00:00+00', :'groupID', :'userID'),
    (:'conversationRecentSecondID', '2030-01-09 13:00:00+00', :'groupID', :'userID');

-- Conversations started at and before the window start by the user below the limits
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, user_id) values
    (:'conversationBoundaryID', '2030-01-09 12:00:00+00', :'groupID', :'userID'),
    (:'conversationOldID', '2030-01-08 12:00:00+00', :'groupID', :'userID');

-- Conversations started inside the window by the limited user
insert into inbox_conversation (inbox_conversation_id, created_at, group_id, user_id) values
    (:'conversationLimitedFirstID', '2030-01-10 01:00:00+00', :'groupID', :'limitedUserID'),
    (:'conversationLimitedSecondID', '2030-01-10 02:00:00+00', :'groupID', :'limitedUserID'),
    (:'conversationLimitedThirdID', '2030-01-10 03:00:00+00', :'groupID', :'limitedUserID');

-- First messages and group replies inside the window that never count as follow-ups
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id) values
    ('First', '2030-01-10 01:00:00+00', :'conversationRecentFirstID', 'initial', :'userID'),
    ('Reply', '2030-01-10 02:00:00+00', :'conversationRecentFirstID', 'group-reply', :'userID');

-- Follow-ups at and before the window start by the user below the limits
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id) values
    ('Boundary', '2030-01-09 12:00:00+00', :'conversationOldID', 'user-reply', :'userID'),
    ('Old', '2030-01-08 12:00:00+00', :'conversationOldID', 'user-reply', :'userID');

-- Nine follow-ups inside the window by the user below the limits
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id)
select 'Follow-up', '2030-01-10 03:00:00+00'::timestamptz + make_interval(mins => n), :'conversationRecentFirstID', 'user-reply', :'userID'
from generate_series(1, 9) n;

-- Ten follow-ups inside the window by the limited user
insert into inbox_message (body, created_at, inbox_conversation_id, kind, author_user_id)
select 'Follow-up', '2030-01-10 03:00:00+00'::timestamptz + make_interval(mins => n), :'conversationLimitedFirstID', 'user-reply', :'limitedUserID'
from generate_series(1, 10) n;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow users below both limits, ignoring rows outside the window and non-follow-up messages
select results_eq(
    format(
        $$select can_send_follow_up, can_start_conversation from inbox_user_rate_limits(%L::uuid, '2030-01-10 12:00:00+00')$$,
        :'userID'
    ),
    $$values (true, true)$$,
    'Should allow users below both limits, ignoring rows outside the window and non-follow-up messages'
);

-- Should block users who reached both limits
select results_eq(
    format(
        $$select can_send_follow_up, can_start_conversation from inbox_user_rate_limits(%L::uuid, '2030-01-10 12:00:00+00')$$,
        :'limitedUserID'
    ),
    $$values (false, false)$$,
    'Should block users who reached both limits'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
