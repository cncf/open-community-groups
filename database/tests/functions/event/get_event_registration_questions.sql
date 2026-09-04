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

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'registration_questions', jsonb_build_array(jsonb_build_object(
        'id', :'questionID',
        'kind', 'free-text',
        'prompt', 'Dietary restrictions?',
        'required', true
    ))
));
select fx_event(:'eventNoQuestionsID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

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
