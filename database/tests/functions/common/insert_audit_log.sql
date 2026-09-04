-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c0c0000-0000-0000-0000-000000000001'
\set eventCategoryID '0c0c0000-0000-0000-0000-000000000002'
\set eventID '0c0c0000-0000-0000-0000-000000000003'
\set groupCategoryID '0c0c0000-0000-0000-0000-000000000004'
\set groupID '0c0c0000-0000-0000-0000-000000000005'
\set userID '0c0c0000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- User
select fx_user(:'userID', jsonb_build_object('username', 'user'));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

-- ============================================================================
-- TESTS
-- ============================================================================

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
            select * from audit_log
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
