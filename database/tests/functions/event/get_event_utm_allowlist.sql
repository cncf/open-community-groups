-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c0b20000-0000-0000-0000-000000000001'
\set eventCategoryID 'c0b20000-0000-0000-0000-000000000002'
\set eventDeletedID 'c0b20000-0000-0000-0000-000000000003'
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

-- Group accepting its own UTM values
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'utm_campaigns', jsonb_build_array('spring-launch'),
    'utm_mediums', jsonb_build_array('podcast'),
    'utm_sources', jsonb_build_array('newsletter', 'partner.site')
));

-- Events with scenario-specific state
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'eventDeletedID', :'groupID', :'eventCategoryID', jsonb_build_object('deleted', true));
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the group values and every accepted medium for a published event
select is(
    get_event_utm_allowlist(:'eventID'::uuid)::jsonb,
    jsonb_build_object(
        'campaigns', jsonb_build_array('spring-launch'),
        'mediums', jsonb_build_array(
            'affiliate',
            'cpc',
            'display',
            'email',
            'organic',
            'podcast',
            'qr',
            'referral',
            'sms',
            'social',
            'video'
        ),
        'sources', jsonb_build_array('newsletter', 'partner.site')
    ),
    'Should return the group values and every accepted medium for a published event'
);

-- Should return null for a deleted event
select is(
    get_event_utm_allowlist(:'eventDeletedID'::uuid)::jsonb,
    null,
    'Should return null for a deleted event'
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
