-- Tests filtering notification recipients before content is built.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedUserID1 '9e030000-0000-0000-0000-000000000001'
\set acceptedUserID2 '9e030000-0000-0000-0000-000000000002'
\set communityID '9e030000-0000-0000-0000-000000000003'
\set groupCategoryID '9e030000-0000-0000-0000-000000000004'
\set groupID '9e030000-0000-0000-0000-000000000005'
\set mutedUserID '9e030000-0000-0000-0000-000000000006'
\set optedOutUserID '9e030000-0000-0000-0000-000000000007'
\set teamOptedOutUserID '9e030000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the muted group
select fx_community(:'communityID');

-- Group category containing the muted group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group named by group-mutable notification filters
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- First accepted user used to prove order is preserved
select fx_user(:'acceptedUserID1');

-- Second accepted user used to prove order is preserved
select fx_user(:'acceptedUserID2');

-- User muted for the notification group
select fx_user(:'mutedUserID');

-- User opted out of event publication notifications
select fx_user(:'optedOutUserID');

-- User opted out of a team notification category
select fx_user(:'teamOptedOutUserID');

-- Opt-out used by category filtering
insert into user_notification_opt_out (notification_category_id, user_id)
values ('new-events', :'optedOutUserID');

-- Opt-out used by team-category filtering
insert into user_notification_opt_out (notification_category_id, user_id)
values ('group-inbox', :'teamOptedOutUserID');

-- Mute used by group filtering
insert into user_group_notification_mute (group_id, user_id)
values (:'groupID', :'mutedUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should preserve input order while filtering category opt-outs and mutes
select is(
    filter_notification_recipient_ids(
        'event-published',
        array[
            :'acceptedUserID2',
            :'mutedUserID',
            :'acceptedUserID1',
            :'optedOutUserID'
        ]::uuid[],
        array[:'groupID']::uuid[]
    ),
    array[:'acceptedUserID2', :'acceptedUserID1']::uuid[],
    'Should preserve input order while filtering category opt-outs and mutes'
);

-- Should filter team categories by opt-out without group ids
select is(
    filter_notification_recipient_ids(
        'inbox-message-received',
        array[:'acceptedUserID1', :'teamOptedOutUserID']::uuid[],
        null::uuid[]
    ),
    array[:'acceptedUserID1']::uuid[],
    'Should filter team categories by opt-out without group ids'
);

-- Should keep always-sent kinds regardless of opt-outs and mutes
select is(
    filter_notification_recipient_ids(
        'event-refund-requested',
        array[:'mutedUserID', :'optedOutUserID']::uuid[],
        array[:'groupID']::uuid[]
    ),
    array[:'mutedUserID', :'optedOutUserID']::uuid[],
    'Should keep always-sent kinds regardless of opt-outs and mutes'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
