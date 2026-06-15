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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Active Group', 'active-group');

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'test_hash', 'user@example.com', true, 'user');

-- Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values (
    :'eventID',
    :'groupID',
    'Test Event',
    'test-event',
    'A test event',
    'UTC',
    :'eventCategoryID',
    'virtual'
);

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
