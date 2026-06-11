-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c030000-0000-0000-0000-000000000001'

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
    'Community for event category tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create a new event category and auto-generate slug
select lives_ok(
    format(
        $$ select add_event_category(
        null::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Cloud Native Meetup')
    ) $$,
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
            null::uuid,
            null::text,
            %L::uuid,
            'event_category',
            event_category_id
        from event_category
        where community_id = %L::uuid
        $$,
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
    'event category name is invalid',
    'Should reject event category names that generate empty slugs'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
