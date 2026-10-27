-- Tests updating dashboard community event categories.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '2c160000-0000-0000-0000-000000000006'
\set communityID '2c160000-0000-0000-0000-000000000001'
\set eventCategory1ID '2c160000-0000-0000-0000-000000000002'
\set eventCategory2ID '2c160000-0000-0000-0000-000000000003'
\set foreignEventCategoryID '2c160000-0000-0000-0000-000000000004'
\set otherCommunityID '2c160000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the taxonomy under test
select fx_community(:'communityID');

-- Other community owning the foreign event category
select fx_community(:'otherCommunityID');

-- Actor recorded in the audit row
select fx_user(:'actorUserID', jsonb_build_object('username', 'update-event-category-audit-actor'));

-- Event category updated by the scenarios
select fx_event_category(:'eventCategory1ID', :'communityID');

-- Second event category whose name the duplicate scenario reuses
select fx_event_category(:'eventCategory2ID', :'communityID', jsonb_build_object('name', 'Conference'));

-- Event category owned by the other community
select fx_event_category(:'foreignEventCategoryID', :'otherCommunityID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should fail when updating an event category from another community
select throws_ok(
    format(
        $$ select update_event_category(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Workshops')
    ) $$,
        :'communityID',
        :'foreignEventCategoryID'
    ),
    'OCG01',
    'event category not found',
    'Should fail when updating an event category from another community'
);

-- Should reject duplicate event category names
select throws_ok(
    format(
        $$ select update_event_category(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Conference')
    ) $$,
        :'communityID',
        :'eventCategory1ID'
    ),
    'OCG01',
    'event category already exists',
    'Should reject duplicate event category names'
);

-- Should reject event category names that generate empty slugs
select throws_ok(
    format(
        $$ select update_event_category(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', '!!!')
    ) $$,
        :'communityID',
        :'eventCategory1ID'
    ),
    'OCG01',
    'event category name is invalid',
    'Should reject event category names that generate empty slugs'
);

-- Should update event category and regenerate slug
select lives_ok(
    format(
        $$ select update_event_category(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Lightning Talks')
    ) $$,
        :'actorUserID',
        :'communityID',
        :'eventCategory1ID'
    ),
    'Should update event category and regenerate slug'
);
select results_eq(
    format(
        $$
    select
        ec.name,
        ec.slug
    from event_category ec
    where ec.event_category_id = %L::uuid
        $$,
        :'eventCategory1ID'
    ),
    $$ values ('Lightning Talks'::text, 'lightning-talks'::text) $$,
    'Should persist updated event category values'
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
        values (
            'event_category_updated',
            %L::uuid,
            'update-event-category-audit-actor',
            %L::uuid,
            'event_category',
            %L::uuid
        )
        $$,
        :'actorUserID',
        :'communityID',
        :'eventCategory1ID'
    ),
    'Should create the expected audit row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
