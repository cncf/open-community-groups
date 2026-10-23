-- Tests inserting audit log entries.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c0c0000-0000-0000-0000-000000000001'
\set eventCategoryID '0c0c0000-0000-0000-0000-000000000002'
\set eventID '0c0c0000-0000-0000-0000-000000000003'
\set groupCategoryID '0c0c0000-0000-0000-0000-000000000004'
\set groupID '0c0c0000-0000-0000-0000-000000000005'
\set otherCommunityID '0c0c0000-0000-0000-0000-000000000007'
\set userID '0c0c0000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the group and event
select fx_community(:'communityID');

-- Community passed explicitly for a group of another community
select fx_community(:'otherCommunityID');

-- Actor whose username is snapshotted
select fx_user(:'userID', jsonb_build_object('username', 'user'));

-- Event category of the event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category of the group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group whose community is derived when omitted
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event scoped by the full audit row
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should derive the community from the group when omitted
select lives_ok(
    format($$select insert_audit_log(
        'group_team_member_added',
        %L::uuid,
        'user',
        %L::uuid,
        p_group_id => %L::uuid
    )$$, :'userID', :'userID', :'groupID'),
    'Should insert a group-scoped audit row without a community'
);

select is(
    (select community_id from audit_log where action = 'group_team_member_added'),
    :'communityID'::uuid,
    'Should derive the community from the group when omitted'
);

-- Should insert an audit row with actor snapshot and default details
select lives_ok(
    format($$select insert_audit_log(
        'community_updated',
        %L::uuid,
        'community',
        %L::uuid,
        %L::uuid
    )$$, :'userID', :'communityID', :'communityID'),
    'Should insert an audit row'
);

select is(
    (
        select row_to_json(t.*)::jsonb - 'audit_log_id' - 'created_at'
        from (
            select *
            from audit_log
            where action = 'community_updated'
        ) t
    ),
    format('{
        "action": "community_updated",
        "actor_user_id": "%s",
        "actor_username": "user",
        "community_id": "%s",
        "details": {},
        "event_id": null,
        "group_id": null,
        "resource_id": "%s",
        "resource_type": "community"
    }', :'userID', :'communityID', :'communityID')::jsonb,
    'Should persist the actor snapshot and normalized details'
);

select is(
    (select created_at from audit_log where action = 'community_updated'),
    now(),
    'Should default the creation time to the transaction time'
);

-- Should keep an explicit community when given
select lives_ok(
    format($$select insert_audit_log(
        'group_team_member_removed',
        %L::uuid,
        'user',
        %L::uuid,
        %L::uuid,
        %L::uuid
    )$$, :'userID', :'userID', :'otherCommunityID', :'groupID'),
    'Should insert a group-scoped audit row with an explicit community'
);

select is(
    (select community_id from audit_log where action = 'group_team_member_removed'),
    :'otherCommunityID'::uuid,
    'Should keep an explicit community when given'
);

-- Should leave community null without a group
select lives_ok(
    format($$select insert_audit_log(
        'user_details_updated',
        %L::uuid,
        'user',
        %L::uuid
    )$$, :'userID', :'userID'),
    'Should insert an audit row without scope ids'
);

select is(
    (select community_id from audit_log where action = 'user_details_updated'),
    null::uuid,
    'Should leave community null without a group'
);

-- Should store an explicit creation time
select lives_ok(
    format($$select insert_audit_log(
        'group_updated',
        %L::uuid,
        'group',
        %L::uuid,
        %L::uuid,
        %L::uuid,
        p_created_at => '2030-01-02 03:04:05+00'::timestamptz
    )$$, :'userID', :'groupID', :'communityID', :'groupID'),
    'Should insert an audit row with an explicit creation time'
);

select is(
    (select created_at from audit_log where action = 'group_updated'),
    '2030-01-02 03:04:05+00'::timestamptz,
    'Should store an explicit creation time'
);

-- Should store optional scope ids and explicit details
select lives_ok(
    format($$select insert_audit_log(
        'event_published',
        %L::uuid,
        'event',
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        '{"subject":"Launch","recipient_count":42}'::jsonb
    )$$, :'userID', :'eventID', :'communityID', :'groupID', :'eventID'),
    'Should insert an audit row with all scope ids'
);

select is(
    (
        select row_to_json(t.*)::jsonb - 'audit_log_id' - 'created_at'
        from (
            select *
            from audit_log
            where action = 'event_published'
        ) t
    ),
    format('{
        "action": "event_published",
        "actor_user_id": "%s",
        "actor_username": "user",
        "community_id": "%s",
        "details": {
            "recipient_count": 42,
            "subject": "Launch"
        },
        "event_id": "%s",
        "group_id": "%s",
        "resource_id": "%s",
        "resource_type": "event"
    }', :'userID', :'communityID', :'eventID', :'groupID', :'eventID')::jsonb,
    'Should persist the full audit row with scope ids and explicit details'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
