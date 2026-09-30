-- Tests unmuting group notifications for a user.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '9e090000-0000-0000-0000-000000000001'
\set disconnectedGroupID '9e090000-0000-0000-0000-000000000002'
\set groupCategoryID '9e090000-0000-0000-0000-000000000003'
\set unavailableGroupID '9e090000-0000-0000-0000-000000000004'
\set userID '9e090000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing muted groups
select fx_community(:'communityID');

-- Group category containing muted groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- User unmuting groups
select fx_user(:'userID');

-- Disconnected muted group
select fx_group(:'disconnectedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Disconnected Muted Group'
));

-- Unavailable muted group
select fx_group(:'unavailableGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'name', 'Unavailable Muted Group'
));

-- Existing mutes removed by the test
insert into user_group_notification_mute (group_id, user_id)
values
    (:'disconnectedGroupID', :'userID'),
    (:'unavailableGroupID', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should unmute unavailable and disconnected groups
select lives_ok(
    format(
        $$
            do $do$
            begin
                perform unmute_user_group_notifications(%L::uuid, %L::uuid);
                perform unmute_user_group_notifications(%L::uuid, %L::uuid);
            end
            $do$;
        $$,
        :'userID',
        :'disconnectedGroupID',
        :'userID',
        :'unavailableGroupID'
    ),
    'Should unmute unavailable and disconnected groups'
);

-- Should delete muted rows
select is(
    (
        select count(*)::int
        from user_group_notification_mute
        where user_id = :'userID'
    ),
    0,
    'Should delete muted rows'
);

-- Should audit only deleted rows and skip repeat unmutes
select lives_ok(
    format(
        $$
            do $do$
            begin
                perform unmute_user_group_notifications(%L::uuid, %L::uuid);

                if (
                    select count(*)::int
                    from audit_log
                    where actor_user_id = %L::uuid
                    and action = 'group_notifications_unmuted'
                ) <> 2 then
                    raise exception 'unexpected unmute audit count';
                end if;
            end
            $do$;
        $$,
        :'userID',
        :'unavailableGroupID',
        :'userID'
    ),
    'Should audit only deleted rows and skip repeat unmutes'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
