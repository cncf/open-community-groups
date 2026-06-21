-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance2ID '00000000-0000-0000-0000-000000000002'
\set allianceID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000031'
\set eventID '00000000-0000-0000-0000-000000000041'
\set eventNoQuestionsID '00000000-0000-0000-0000-000000000042'
\set groupCategoryID '00000000-0000-0000-0000-000000000011'
\set groupID '00000000-0000-0000-0000-000000000021'
\set questionID '00000000-0000-0000-0000-000000000051'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliances
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'allianceID', 'questionnaire-alliance', 'Questionnaire Alliance', 'Desc', 'https://example.test/logo.png', 'https://example.test/mobile.png', 'https://example.test/banner.png'),
    (:'alliance2ID', 'other-alliance', 'Other Alliance', 'Desc', 'https://example.test/other.png', 'https://example.test/other-mobile.png', 'https://example.test/other-banner.png');

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Meetup');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Questionnaire Group', 'questionnaire-group');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Meetups');

-- Events
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    registration_questions,
    slug,
    timezone
) values (
    :'eventID',
    'Event with registration questions',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Questionnaire Event',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID',
        'kind', 'free-text',
        'prompt', 'Dietary restrictions?',
        'required', true
    )),
    'questionnaire-event',
    'UTC'
), (
    :'eventNoQuestionsID',
    'Event without registration questions',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'No Questions Event',
    '[]'::jsonb,
    'no-questions-event',
    'UTC'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return configured registration questions
select is(
    get_event_registration_questions(:'allianceID'::uuid, :'eventID'::uuid)::jsonb,
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID',
        'kind', 'free-text',
        'prompt', 'Dietary restrictions?',
        'required', true
    )),
    'Should return configured registration questions'
);

-- Should return an empty array when questions are not configured
select is(
    get_event_registration_questions(:'allianceID'::uuid, :'eventNoQuestionsID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return an empty array when questions are not configured'
);

-- Should return null when alliance mismatches
select ok(
    get_event_registration_questions(:'alliance2ID'::uuid, :'eventID'::uuid) is null,
    'Should return null when the event belongs to another alliance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
