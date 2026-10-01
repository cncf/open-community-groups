-- Tests whether spam reports block a user from contacting a group.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set closedUserID '1b160000-0000-0000-0000-000000000001'
\set communityID '1b160000-0000-0000-0000-000000000002'
\set conversationClosedFirstID '1b160000-0000-0000-0000-000000000003'
\set conversationClosedSecondID '1b160000-0000-0000-0000-000000000004'
\set conversationClosedThirdID '1b160000-0000-0000-0000-000000000005'
\set conversationOnceID '1b160000-0000-0000-0000-000000000006'
\set conversationOtherCommunityID '1b160000-0000-0000-0000-000000000007'
\set conversationRepeatedFirstID '1b160000-0000-0000-0000-000000000008'
\set conversationRepeatedSecondID '1b160000-0000-0000-0000-000000000009'
\set conversationRepeatedThirdID '1b160000-0000-0000-0000-000000000010'
\set conversationReportedFirstID '1b160000-0000-0000-0000-000000000011'
\set conversationReportedSecondID '1b160000-0000-0000-0000-000000000012'
\set conversationReportedThirdID '1b160000-0000-0000-0000-000000000013'
\set conversationSpreadFirstID '1b160000-0000-0000-0000-000000000014'
\set conversationSpreadSecondID '1b160000-0000-0000-0000-000000000015'
\set groupCategoryID '1b160000-0000-0000-0000-000000000016'
\set groupFirstID '1b160000-0000-0000-0000-000000000017'
\set groupFourthID '1b160000-0000-0000-0000-000000000018'
\set groupSecondID '1b160000-0000-0000-0000-000000000019'
\set groupThirdID '1b160000-0000-0000-0000-000000000020'
\set onceUserID '1b160000-0000-0000-0000-000000000021'
\set otherCommunityGroupCategoryID '1b160000-0000-0000-0000-000000000022'
\set otherCommunityGroupID '1b160000-0000-0000-0000-000000000023'
\set otherCommunityID '1b160000-0000-0000-0000-000000000024'
\set repeatedUserID '1b160000-0000-0000-0000-000000000025'
\set reportedUserID '1b160000-0000-0000-0000-000000000026'
\set spreadUserID '1b160000-0000-0000-0000-000000000027'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose groups report spam
select fx_community(:'communityID');

-- Another community
select fx_community(:'otherCommunityID');

-- User whose conversations were closed but never reported
select fx_user(:'closedUserID');

-- User reported once
select fx_user(:'onceUserID');

-- User reported repeatedly by the same groups
select fx_user(:'repeatedUserID');

-- User reported by three groups of the community
select fx_user(:'reportedUserID');

-- User reported by groups of two communities
select fx_user(:'spreadUserID');

-- Group category of the community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category of the other community
select fx_group_category(:'otherCommunityGroupCategoryID', :'otherCommunityID');

-- First group of the community
select fx_group(:'groupFirstID', :'communityID', :'groupCategoryID');

-- Fourth group of the community, which never reported anyone
select fx_group(:'groupFourthID', :'communityID', :'groupCategoryID');

-- Second group of the community
select fx_group(:'groupSecondID', :'communityID', :'groupCategoryID');

-- Third group of the community
select fx_group(:'groupThirdID', :'communityID', :'groupCategoryID');

-- Group of the other community
select fx_group(:'otherCommunityGroupID', :'otherCommunityID', :'otherCommunityGroupCategoryID');

-- Closed conversations with three groups of the community
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, user_id) values
    (:'conversationClosedFirstID', :'groupFirstID', 'closed', :'closedUserID'),
    (:'conversationClosedSecondID', :'groupSecondID', 'closed', :'closedUserID'),
    (:'conversationClosedThirdID', :'groupThirdID', 'closed', :'closedUserID');

-- Conversation marked as spam by one group
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, user_id)
values (:'conversationOnceID', :'groupFirstID', 'spam', :'onceUserID');

-- Three conversations marked as spam by two groups of the community
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, user_id) values
    (:'conversationRepeatedFirstID', :'groupFirstID', 'spam', :'repeatedUserID'),
    (:'conversationRepeatedSecondID', :'groupFirstID', 'spam', :'repeatedUserID'),
    (:'conversationRepeatedThirdID', :'groupSecondID', 'spam', :'repeatedUserID');

-- Conversations marked as spam by three groups of the community
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, user_id) values
    (:'conversationReportedFirstID', :'groupFirstID', 'spam', :'reportedUserID'),
    (:'conversationReportedSecondID', :'groupSecondID', 'spam', :'reportedUserID'),
    (:'conversationReportedThirdID', :'groupThirdID', 'spam', :'reportedUserID');

-- Conversations marked as spam by two groups of the community and one of another community
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, user_id) values
    (:'conversationOtherCommunityID', :'otherCommunityGroupID', 'spam', :'spreadUserID'),
    (:'conversationSpreadFirstID', :'groupFirstID', 'spam', :'spreadUserID'),
    (:'conversationSpreadSecondID', :'groupSecondID', 'spam', :'spreadUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block users from every group of a community after reports from three of its groups
select is(
    is_inbox_user_blocked(:'groupFourthID'::uuid, :'reportedUserID'::uuid),
    true,
    'Should block users from every group of a community after reports from three of its groups'
);

-- Should block users from the group that marked their conversation as spam
select is(
    is_inbox_user_blocked(:'groupFirstID'::uuid, :'onceUserID'::uuid),
    true,
    'Should block users from the group that marked their conversation as spam'
);

-- Should count each reporting group once
select is(
    is_inbox_user_blocked(:'groupFourthID'::uuid, :'repeatedUserID'::uuid),
    false,
    'Should count each reporting group once'
);

-- Should ignore conversations that are not marked as spam
select is(
    is_inbox_user_blocked(:'groupFirstID'::uuid, :'closedUserID'::uuid),
    false,
    'Should ignore conversations that are not marked as spam'
);

-- Should ignore reports from groups of other communities
select is(
    is_inbox_user_blocked(:'groupFourthID'::uuid, :'spreadUserID'::uuid),
    false,
    'Should ignore reports from groups of other communities'
);

-- Should not block users from other groups after a single report
select is(
    is_inbox_user_blocked(:'groupSecondID'::uuid, :'onceUserID'::uuid),
    false,
    'Should not block users from other groups after a single report'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
