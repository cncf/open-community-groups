-- Tests adding dashboard community event categories.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '2c030000-0000-0000-0000-000000000002'
\set communityID '2c030000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community
select fx_community(:'communityID');

-- Actor recorded in the audit row
select fx_user(:'actorUserID', jsonb_build_object('username', 'add-event-category-audit-actor'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create a new event category and auto-generate slug
select lives_ok(
    format(
        $$ select add_event_category(
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Cloud Native Meetup')
    ) $$,
        :'actorUserID',
        :'communityID'
    ),
    'Should create an event category with generated slug'
);
select results_eq(
    format(
        $$
    select
        ec.name,
        ec.slug
    from event_category ec
    where ec.community_id = %L::uuid
        $$,
        :'communityID'
    ),
    $$ values ('Cloud Native Meetup'::text, 'cloud-native-meetup'::text) $$,
    'Should store category name and generated slug'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        select
            'event_category_added',
            %L::uuid,
            'add-event-category-audit-actor',
            %L::uuid,
            'event_category',
            event_category_id
        from event_category
        where community_id = %L::uuid
        $$,
        :'actorUserID',
        :'communityID',
        :'communityID'
    ),
    'Should create the expected audit row'
);

-- Should not allow duplicate event category slug in same community
select throws_ok(
    format(
        $$ select add_event_category(
        null::uuid,
        %L::uuid,
        jsonb_build_object('name', 'cloud native meetup')
    ) $$,
        :'communityID'
    ),
    'OCG01',
    'event category already exists',
    'Should reject duplicate event category names'
);

-- Should reject names that generate an empty slug
select throws_ok(
    format(
        $$ select add_event_category(
        null::uuid,
        %L::uuid,
        jsonb_build_object('name', '!!!')
    ) $$,
        :'communityID'
    ),
    'OCG01',
    'event category name is invalid',
    'Should reject event category names that generate empty slugs'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
