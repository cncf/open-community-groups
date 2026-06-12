-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c080000-0000-0000-0000-000000000001'
\set eventCategoryID '0c080000-0000-0000-0000-000000000002'
\set eventID '0c080000-0000-0000-0000-000000000003'
\set eventNoQuestionsID '0c080000-0000-0000-0000-000000000004'
\set groupCategoryID '0c080000-0000-0000-0000-000000000005'
\set groupID '0c080000-0000-0000-0000-000000000006'
\set otherCommunityID '0c080000-0000-0000-0000-000000000007'
\set questionID '0c080000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
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
    'questionnaire-community',
    'Questionnaire Community',
    'Community for registration question tests',
    'https://example.test/mobile.png',
    'https://example.test/banner.png',
    'https://example.test/logo.png'
), (
    :'otherCommunityID',
    'other-questionnaire-community',
    'Other Questionnaire Community',
    'Second community for mismatch tests',
    'https://example.test/other-mobile.png',
    'https://example.test/other-banner.png',
    'https://example.test/other.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Meetup');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetups');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Questionnaire Group',
    'questionnaire-group'
);

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
    get_event_registration_questions(:'communityID'::uuid, :'eventID'::uuid)::jsonb,
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
    get_event_registration_questions(:'communityID'::uuid, :'eventNoQuestionsID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return an empty array when questions are not configured'
);

-- Should return null when community mismatches
select ok(
    get_event_registration_questions(:'otherCommunityID'::uuid, :'eventID'::uuid) is null,
    'Should return null when the event belongs to another community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
