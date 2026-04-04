-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventID '00000000-0000-0000-0000-000000000031'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000021'
\set userID '00000000-0000-0000-0000-000000000041'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Active Group', 'active-group');

-- User
insert into "user" (user_id, auth_hash, email, username)
values (:'userID', 'hash', 'user@example.com', 'user');

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
    $$select insert_audit_log(
        'community_updated',
        '00000000-0000-0000-0000-000000000041'::uuid,
        'community',
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000001'::uuid
    )$$,
    'Should insert an audit row'
);

select is(
    (
        select row_to_json(t.*)::jsonb - 'audit_log_id' - 'created_at'
        from (
            select * from audit_log
        ) t
    ),
    '{
        "action": "community_updated",
        "actor_user_id": "00000000-0000-0000-0000-000000000041",
        "actor_username": "user",
        "community_id": "00000000-0000-0000-0000-000000000001",
        "details": {},
        "event_id": null,
        "group_id": null,
        "resource_id": "00000000-0000-0000-0000-000000000001",
        "resource_type": "community"
    }'::jsonb,
    'Should persist the actor snapshot and normalized details'
);

-- Should store optional scope ids and explicit details
select lives_ok(
    $$select insert_audit_log(
        'event_published',
        '00000000-0000-0000-0000-000000000041'::uuid,
        'event',
        '00000000-0000-0000-0000-000000000031'::uuid,
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000021'::uuid,
        '00000000-0000-0000-0000-000000000031'::uuid,
        '{"subject":"Launch","recipient_count":42}'::jsonb
    )$$,
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
    '{
        "action": "event_published",
        "actor_user_id": "00000000-0000-0000-0000-000000000041",
        "actor_username": "user",
        "community_id": "00000000-0000-0000-0000-000000000001",
        "details": {
            "recipient_count": 42,
            "subject": "Launch"
        },
        "event_id": "00000000-0000-0000-0000-000000000031",
        "group_id": "00000000-0000-0000-0000-000000000021",
        "resource_id": "00000000-0000-0000-0000-000000000031",
        "resource_type": "event"
    }'::jsonb,
    'Should persist the full audit row with scope ids and explicit details'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
