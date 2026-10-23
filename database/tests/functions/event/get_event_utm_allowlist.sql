-- Tests returning the UTM values accepted for event views.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c0b20000-0000-0000-0000-000000000001'
\set eventCategoryID 'c0b20000-0000-0000-0000-000000000002'
\set eventID 'c0b20000-0000-0000-0000-000000000004'
\set eventUnpublishedID 'c0b20000-0000-0000-0000-000000000005'
\set groupCategoryID 'c0b20000-0000-0000-0000-000000000006'
\set groupID 'c0b20000-0000-0000-0000-000000000007'
\set missingEventID 'c0b20000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group category and event category
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group accepting its own UTM values, with one medium repeating a default
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'utm_campaigns', jsonb_build_array('spring-launch'),
    'utm_mediums', jsonb_build_array('podcast', 'email'),
    'utm_sources', jsonb_build_array('newsletter', 'partner.site')
));

-- Published event whose group values are returned
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Unpublished event without an allowlist
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should include every default medium and the group extra mediums
select ok(
    get_event_utm_allowlist(:'eventID'::uuid)::jsonb->'mediums'
        @> (select jsonb_agg(utm_medium_id) from utm_medium)
    and get_event_utm_allowlist(:'eventID'::uuid)::jsonb->'mediums' ? 'podcast',
    'Should include every default medium and the group extra mediums'
);

-- Should list a group medium repeating a default once
select is(
    (
        select count(*)
        from json_array_elements_text(get_event_utm_allowlist(:'eventID'::uuid)->'mediums') as m
        where m = 'email'
    ),
    1::bigint,
    'Should list a group medium repeating a default once'
);

-- Should return mediums sorted and distinct
select is(
    (
        select array_agg(t.m order by t.position)
        from json_array_elements_text(get_event_utm_allowlist(:'eventID'::uuid)->'mediums')
            with ordinality as t(m, position)
    ),
    (
        select array_agg(distinct m order by m)
        from json_array_elements_text(get_event_utm_allowlist(:'eventID'::uuid)->'mediums') as m
    ),
    'Should return mediums sorted and distinct'
);

-- Should return null for a missing event
select is(
    get_event_utm_allowlist(:'missingEventID'::uuid)::jsonb,
    null,
    'Should return null for a missing event'
);

-- Should return null for an unpublished event
select is(
    get_event_utm_allowlist(:'eventUnpublishedID'::uuid)::jsonb,
    null,
    'Should return null for an unpublished event'
);

-- Should return the group campaigns and sources for a published event
select is(
    get_event_utm_allowlist(:'eventID'::uuid)::jsonb - 'mediums',
    jsonb_build_object(
        'campaigns', jsonb_build_array('spring-launch'),
        'sources', jsonb_build_array('newsletter', 'partner.site')
    ),
    'Should return the group campaigns and sources for a published event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
