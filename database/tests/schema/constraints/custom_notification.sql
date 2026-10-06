-- Tests custom notification constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cascadeCommunityID '8a110000-0000-0000-0000-000000000001'
\set cascadeNotificationID '8a110000-0000-0000-0000-000000000002'
\set communityID '8a110000-0000-0000-0000-000000000003'
\set eventCategoryID '8a110000-0000-0000-0000-000000000004'
\set eventID '8a110000-0000-0000-0000-000000000005'
\set groupCategoryID '8a110000-0000-0000-0000-000000000006'
\set groupID '8a110000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community deleted by the cascade scenario
select fx_community(:'cascadeCommunityID');

-- Community scoping the constraint scenarios
select fx_community(:'communityID');

-- Community notification deleted through community cascade
insert into custom_notification (custom_notification_id, body, community_id, subject)
values (:'cascadeNotificationID', 'Cascade body', :'cascadeCommunityID', 'Cascade subject');

-- Event category of the scoped event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category of the scoped group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group scoping the constraint scenarios
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event scoping the constraint scenarios
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept community-scoped notifications
select lives_ok(
    format(
        $$
            insert into custom_notification (body, community_id, subject)
            values ('Body', %L::uuid, 'Community scope')
        $$,
        :'communityID'
    ),
    'Should accept community-scoped notifications'
);

-- Should accept event-scoped notifications
select lives_ok(
    format(
        $$
            insert into custom_notification (body, event_id, subject)
            values ('Body', %L::uuid, 'Event scope')
        $$,
        :'eventID'
    ),
    'Should accept event-scoped notifications'
);

-- Should accept group-scoped notifications
select lives_ok(
    format(
        $$
            insert into custom_notification (body, group_id, subject)
            values ('Body', %L::uuid, 'Group scope')
        $$,
        :'groupID'
    ),
    'Should accept group-scoped notifications'
);

-- Should delete community notifications when communities are deleted
select lives_ok(
    format($$delete from community where community_id = %L::uuid$$, :'cascadeCommunityID'),
    'Should delete communities with custom notifications'
);
select is(
    (
        select count(*)::int
        from custom_notification
        where custom_notification_id = :'cascadeNotificationID'
    ),
    0,
    'Should delete community notifications when communities are deleted'
);

-- Should reject notifications with every scope
select throws_ok(
    format(
        $$
            insert into custom_notification (body, community_id, event_id, group_id, subject)
            values ('Body', %L::uuid, %L::uuid, %L::uuid, 'Every scope')
        $$,
        :'communityID',
        :'eventID',
        :'groupID'
    ),
    '23514',
    null,
    'Should reject notifications with every scope'
);

-- Should reject notifications with two scopes
select throws_ok(
    format(
        $$
            insert into custom_notification (body, community_id, group_id, subject)
            values ('Body', %L::uuid, %L::uuid, 'Two scopes')
        $$,
        :'communityID',
        :'groupID'
    ),
    '23514',
    null,
    'Should reject notifications with two scopes'
);

-- Should reject notifications without a scope
select throws_ok(
    $$
        insert into custom_notification (body, subject)
        values ('Body', 'No scope')
    $$,
    '23514',
    null,
    'Should reject notifications without a scope'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
