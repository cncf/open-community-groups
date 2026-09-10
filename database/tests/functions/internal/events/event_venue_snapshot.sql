-- Tests capturing an event venue as a stored snapshot.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set blankVenueEventID 'f2040000-0000-0000-0000-000000000001'
\set communityID 'f2040000-0000-0000-0000-000000000002'
\set eventCategoryID 'f2040000-0000-0000-0000-000000000003'
\set groupCategoryID 'f2040000-0000-0000-0000-000000000004'
\set groupID 'f2040000-0000-0000-0000-000000000005'
\set venueEventID 'f2040000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event with a full venue, including surrounding whitespace
select fx_event(:'venueEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'venue_address', ' 1 Main St ',
    'venue_city', 'Springfield',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Town Hall',
    'venue_state_code', 'IL',
    'venue_state_name', 'Illinois',
    'venue_zip_code', '62701'
));

-- Event with only a venue name
select fx_event(:'blankVenueEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'venue_name', 'Online Only'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should capture trimmed venue fields
select is(
    (select event_venue_snapshot(e) from event e where e.event_id = :'venueEventID'),
    jsonb_build_object(
        'address', '1 Main St',
        'city', 'Springfield',
        'country_code', 'US',
        'name', 'Town Hall',
        'state_code', 'IL',
        'state_name', 'Illinois',
        'zip_code', '62701'
    ),
    'Should capture trimmed venue fields'
);

-- Should store missing fields as nulls
select is(
    (select event_venue_snapshot(e) from event e where e.event_id = :'blankVenueEventID'),
    jsonb_build_object(
        'address', null,
        'city', null,
        'country_code', null,
        'name', 'Online Only',
        'state_code', null,
        'state_name', null,
        'zip_code', null
    ),
    'Should store missing fields as nulls'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
