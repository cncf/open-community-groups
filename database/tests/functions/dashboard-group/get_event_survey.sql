-- Tests loading a survey of a group event for the editor.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'a5e00012-0000-0000-0000-000000000001'
\set eventCategoryID 'a5e00012-0000-0000-0000-000000000004'
\set eventID 'a5e00012-0000-0000-0000-000000000005'
\set foreignGroupID 'a5e00012-0000-0000-0000-000000000006'
\set groupCategoryID 'a5e00012-0000-0000-0000-000000000007'
\set groupID 'a5e00012-0000-0000-0000-000000000008'
\set plainSurveyID 'a5e00012-0000-0000-0000-00000000000c'
\set questionID 'a5e00012-0000-0000-0000-00000000000a'
\set surveyID 'a5e00012-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group that does not own the surveyed event
select fx_group(:'foreignGroupID', :'communityID', :'groupCategoryID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event owning the survey
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2025-01-01 12:00:00+00',
    'published', true,
    'starts_at', '2025-01-01 10:00:00+00'
));

-- Survey without description or opening
insert into event_survey (event_survey_id, created_at, event_id, title)
values (:'plainSurveyID', '2025-01-01 08:00:00+00', :'eventID', 'Plain survey');

-- Survey with every editor field set
insert into event_survey (
    event_survey_id,
    created_at,
    event_id,
    questions,
    title,

    closes_at,
    description,
    opens_at,
    updated_at
) values (
    :'surveyID',
    '2025-01-01 08:00:00+00',
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'Editor survey',

    '2099-01-01 00:00:00+00',
    'Tell us how it went',
    '2025-01-02 10:00:00+00',
    '2025-01-01 09:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return a null description and opening for surveys without them
select is(
    get_event_survey(:'groupID'::uuid, :'eventID'::uuid, :'plainSurveyID'::uuid)::jsonb,
    (
        select event_survey_summary_json(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'plainSurveyID'
    ) || jsonb_build_object(
        'created_at', 1735718400,
        'questions', '[]'::jsonb,

        'closed_at', null,
        'description', null,
        'opens_at', null,
        'updated_at', null
    ),
    'Should return a null description and opening for surveys without them'
);

-- Should return null for surveys of another group
select is(
    get_event_survey(:'foreignGroupID'::uuid, :'eventID'::uuid, :'surveyID'::uuid)::jsonb,
    null,
    'Should return null for surveys of another group'
);

-- Should return null without a survey id
select is(
    get_event_survey(:'groupID'::uuid, :'eventID'::uuid, null)::jsonb,
    null,
    'Should return null without a survey id'
);

-- Should return the summary with the editor fields
select is(
    get_event_survey(:'groupID'::uuid, :'eventID'::uuid, :'surveyID'::uuid)::jsonb,
    (
        select event_survey_summary_json(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'surveyID'
    ) || jsonb_build_object(
        'created_at', 1735718400,
        'questions', jsonb_build_array(jsonb_build_object(
            'id', :'questionID'::uuid,
            'kind', 'free-text',
            'prompt', 'Feedback',
            'required', false
        )),

        'closed_at', null,
        'description', 'Tell us how it went',
        'opens_at', 1735812000,
        'updated_at', 1735722000
    ),
    'Should return the summary with the editor fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
