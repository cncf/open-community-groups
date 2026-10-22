-- Tests returning public full event information by slug.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '5e060000-0000-0000-0000-000000000014'
\set communityID '5e060000-0000-0000-0000-000000000001'
\set event2ID '5e060000-0000-0000-0000-000000000015'
\set eventCanceledID '5e060000-0000-0000-0000-000000000002'
\set eventCategory2ID '5e060000-0000-0000-0000-000000000016'
\set eventCategoryID '5e060000-0000-0000-0000-000000000003'
\set eventID '5e060000-0000-0000-0000-000000000006'
\set eventUnpublishedID '5e060000-0000-0000-0000-000000000004'
\set group2ID '5e060000-0000-0000-0000-000000000017'
\set groupCategory2ID '5e060000-0000-0000-0000-000000000018'
\set groupCategoryID '5e060000-0000-0000-0000-000000000008'
\set groupID '5e060000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and event categories
select fx_community(:'communityID');
select fx_community(:'community2ID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group_category(:'groupCategory2ID', :'community2ID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_event_category(:'eventCategory2ID', :'community2ID');

-- Group with scenario-specific state
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'created_at', '2025-02-11 10:00:00+00',
    'slug', 'abc1234',
    'slug_pretty', 'test-group-pretty'
));

-- Published event returned by both group slugs
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 500,
    'ends_at', '2024-06-15 17:00:00+00',
    'event_kind_id', 'hybrid',
    'luma_url', 'https://luma.com/event123',
    'meeting_in_sync', true,
    'meeting_join_url', 'https://stream.example.com/live',
    'meeting_recording_url', 'https://youtube.com/watch?v=123',
    'meeting_requested', false,
    'meetup_url', 'https://meetup.com/event123',
    'photos_urls', array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    'published', true,
    'slug', 'def5678',
    'starts_at', '2024-06-15 09:00:00+00',
    'tags', array['technology', 'conference', 'workshops'],
    'timezone', 'America/New_York',
    'venue_address', '123 Main St',
    'venue_city', 'New York',
    'venue_name', 'Convention Center',
    'venue_zip_code', '10001'
));

-- Published canceled event available by slug
select fx_event(:'eventCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'event_kind_id', 'virtual',
    'published', true,
    'slug', 'canceled-tech-conference-2024',
    'starts_at', '2024-06-17 09:00:00+00',
    'timezone', 'America/New_York'
));

-- Group in the other community reusing the same group slug
select fx_group(:'group2ID', :'community2ID', :'groupCategory2ID', jsonb_build_object(
    'slug', 'abc1234'
));

-- Published event in the other community reusing the same event slug
select fx_event(:'event2ID', :'group2ID', :'eventCategory2ID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'slug', 'def5678',
    'starts_at', '2024-06-19 09:00:00+00',
    'timezone', 'America/New_York'
));

-- Unpublished event excluded from public lookup
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'slug', 'unpublished-tech-conference-2024',
    'starts_at', '2024-06-18 09:00:00+00',
    'timezone', 'America/New_York'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should resolve event by group pretty slug
select is(
    (
        select jsonb_build_object('event_id', e->>'event_id', 'payload', e)
        from (
            select get_event_full_by_slug(:'communityID'::uuid, 'test-group-pretty', 'def5678')::jsonb as e
        ) as slug_event
    ),
    jsonb_build_object(
        'event_id', :'eventID',
        'payload', get_public_event_full(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb
    ),
    'Should resolve event by group pretty slug'
);

-- Should return a canceled event when it remains published
select is(
    (
        select jsonb_build_object('event_id', e->>'event_id', 'payload', e)
        from (
            select get_event_full_by_slug(
                :'communityID'::uuid,
                'abc1234',
                'canceled-tech-conference-2024'
            )::jsonb as e
        ) as slug_event
    ),
    jsonb_build_object(
        'event_id', :'eventCanceledID',
        'payload', get_public_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventCanceledID'::uuid
        )::jsonb
    ),
    'Should return a canceled event when it remains published'
);

-- Should scope slug lookup to the requested community
select is(
    jsonb_build_array(
        get_event_full_by_slug(:'communityID'::uuid, 'abc1234', 'def5678')::jsonb->>'event_id',
        get_event_full_by_slug(:'community2ID'::uuid, 'abc1234', 'def5678')::jsonb->>'event_id'
    ),
    jsonb_build_array(:'eventID', :'event2ID'),
    'Should scope slug lookup to the requested community'
);

-- Should return null with non-existing event slug
select ok(
    get_event_full_by_slug(:'communityID'::uuid, 'abc1234', 'non-existing-event') is null,
    'Should return null with non-existing event slug'
);

-- Should return null with unpublished event slug
select ok(
    get_event_full_by_slug(:'communityID'::uuid, 'abc1234', 'unpublished-tech-conference-2024') is null,
    'Should return null with unpublished event slug'
);

-- Should return the same payload as get_public_event_full
select is(
    (
        select jsonb_build_object('event_id', e->>'event_id', 'payload', e)
        from (
            select get_event_full_by_slug(:'communityID'::uuid, 'abc1234', 'def5678')::jsonb as e
        ) as slug_event
    ),
    jsonb_build_object(
        'event_id', :'eventID',
        'payload', get_public_event_full(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb
    ),
    'Should return the same payload as get_public_event_full'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
