-- Tests muting group notifications for a user.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '9e080000-0000-0000-0000-000000000001'
\set connectedGroupID '9e080000-0000-0000-0000-000000000002'
\set disconnectedGroupID '9e080000-0000-0000-0000-000000000003'
\set groupCategoryID '9e080000-0000-0000-0000-000000000004'
\set unavailableMutedGroupID '9e080000-0000-0000-0000-000000000005'
\set unknownGroupID '9e080000-0000-0000-0000-000000000006'
\set userID '9e080000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing mute test groups
select fx_community(:'communityID');

-- Group category containing mute test groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- User muting groups
select fx_user(:'userID');

-- Connected group available to mute
select fx_group(:'connectedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Connected Mute Group'
));

-- Disconnected group rejected by mute validation
select fx_group(:'disconnectedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Disconnected Mute Group'
));

-- Unavailable group already muted before the request
select fx_group(:'unavailableMutedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'name', 'Unavailable Already Muted Group'
));

-- Groups used to prove there is no mute cap
insert into "group" (community_id, group_category_id, group_id, name, slug)
select
    :'communityID',
    :'groupCategoryID',
    ('9e080000-0000-0000-0000-' || lpad(to_hex(100 + i), 12, '0'))::uuid,
    'Bulk Mute Group ' || i,
    'bulk-mute-group-' || i
from generate_series(1, 26) as s(i);

-- Membership connecting the user to the available group
insert into group_member (group_id, user_id)
values (:'connectedGroupID', :'userID');

-- Membership connecting the user to every bulk mute group
insert into group_member (group_id, user_id)
select ('9e080000-0000-0000-0000-' || lpad(to_hex(100 + i), 12, '0'))::uuid, :'userID'
from generate_series(1, 26) as s(i);

-- Existing mute that should remain idempotent after the group becomes unavailable
insert into user_group_notification_mute (group_id, user_id)
values (:'unavailableMutedGroupID', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should mute a connected group
select lives_ok(
    format(
        $$select mute_user_group_notifications(%L::uuid, %L::uuid)$$,
        :'userID',
        :'connectedGroupID'
    ),
    'Should mute a connected group'
);

-- Should insert and audit connected group mutes without group audit scope
select results_eq(
    format(
        $$
            select
                ugm.group_id,
                al.action,
                al.group_id,
                al.resource_id,
                al.resource_type,
                al.details
            from user_group_notification_mute ugm
            join audit_log al on al.resource_id = ugm.user_id
            where ugm.user_id = %L::uuid
            and ugm.group_id = %L::uuid
            and al.action = 'group_notifications_muted'
        $$,
        :'userID',
        :'connectedGroupID'
    ),
    format(
        $$ values (
            %L::uuid,
            'group_notifications_muted'::text,
            null::uuid,
            %L::uuid,
            'user'::text,
            jsonb_build_object('group_id', %L::uuid, 'group_name', 'Connected Mute Group')
        ) $$,
        :'connectedGroupID',
        :'userID',
        :'connectedGroupID'
    ),
    'Should insert and audit connected group mutes without group audit scope'
);

-- Should treat already-muted unavailable groups as a no-op
select lives_ok(
    format(
        $$select mute_user_group_notifications(%L::uuid, %L::uuid)$$,
        :'userID',
        :'unavailableMutedGroupID'
    ),
    'Should treat already-muted unavailable groups as a no-op'
);

-- Should reject disconnected groups
select throws_ok(
    format(
        $$select mute_user_group_notifications(%L::uuid, %L::uuid)$$,
        :'userID',
        :'disconnectedGroupID'
    ),
    'OCG01',
    'group not available to mute',
    'Should reject disconnected groups'
);

-- Should reject unknown groups
select throws_ok(
    format(
        $$select mute_user_group_notifications(%L::uuid, %L::uuid)$$,
        :'userID',
        :'unknownGroupID'
    ),
    'OCG01',
    'group not available to mute',
    'Should reject unknown groups'
);

-- Should store more than twenty-five mutes
select lives_ok(
    format(
        $$
            do $do$
            declare
                v_group_id uuid;
            begin
                for v_group_id in
                    select ('9e080000-0000-0000-0000-' || lpad(to_hex(100 + i), 12, '0'))::uuid
                    from generate_series(1, 26) as s(i)
                loop
                    perform mute_user_group_notifications(%L::uuid, v_group_id);
                end loop;

                if (
                    select count(*)::int
                    from user_group_notification_mute
                    where user_id = %L::uuid
                    and group_id in (
                        select ('9e080000-0000-0000-0000-' || lpad(to_hex(100 + i), 12, '0'))::uuid
                        from generate_series(1, 26) as s(i)
                    )
                ) <> 26 then
                    raise exception 'bulk mutes were not stored';
                end if;
            end
            $do$;
        $$,
        :'userID',
        :'userID'
    ),
    'Should store more than twenty-five mutes'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
