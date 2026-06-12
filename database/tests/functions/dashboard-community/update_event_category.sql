-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c160000-0000-0000-0000-000000000001'
\set eventCategory1ID '2c160000-0000-0000-0000-000000000002'
\set eventCategory2ID '2c160000-0000-0000-0000-000000000003'
\set unknownEventCategoryID '2c160000-0000-0000-0000-000000000004'

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
    'cncf-seattle',
    'CNCF Seattle',
    'Community for event category update tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event categories
insert into event_category (
    event_category_id,
    community_id,
    name
) values
    (:'eventCategory1ID', :'communityID', 'Meetup'),
    (:'eventCategory2ID', :'communityID', 'Conference');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update category name and regenerate slug
select lives_ok(
    format(
        $$ select update_event_category(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Lightning Talks')
    ) $$,
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
            null::uuid,
            null::text,
            %L::uuid,
            'event_category',
            %L::uuid
        )
        $$,
        :'communityID',
        :'eventCategory1ID'
    ),
    'Should create the expected audit row'
);

-- Should reject duplicated slug in same community
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
    'event category already exists',
    'Should reject duplicate event category names'
);

-- Should reject names that generate an empty slug
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
    'event category name is invalid',
    'Should reject event category names that generate empty slugs'
);

-- Should fail when target category does not exist
select throws_ok(
    format(
        $$ select update_event_category(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Workshops')
    ) $$,
        :'communityID',
        :'unknownEventCategoryID'
    ),
    'event category not found',
    'Should fail when updating a non-existing event category'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
