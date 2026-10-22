-- Tests listing and searching the respondents of a survey.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adaUserID 'a5e0001b-0000-0000-0000-000000000001'
\set communityID 'a5e0001b-0000-0000-0000-000000000002'
\set eventCategoryID 'a5e0001b-0000-0000-0000-000000000003'
\set eventID 'a5e0001b-0000-0000-0000-000000000004'
\set graceUserID 'a5e0001b-0000-0000-0000-000000000005'
\set groupCategoryID 'a5e0001b-0000-0000-0000-000000000006'
\set groupID 'a5e0001b-0000-0000-0000-000000000007'
\set linusUserID 'a5e0001b-0000-0000-0000-000000000008'
\set otherSurveyID 'a5e0001b-0000-0000-0000-000000000009'
\set otherSurveyUserID 'a5e0001b-0000-0000-0000-00000000000a'
\set surveyID 'a5e0001b-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed event
select fx_community(:'communityID');

-- Respondent with every profile detail and a searchable email
select fx_user(:'adaUserID', jsonb_build_object(
    'company', 'Analytical Engines',
    'email', 'ada.mail@example.test',
    'name', 'Ada Lovelace',
    'title', 'Countess',
    'username', 'ada-l'
));

-- Respondent whose company contains a search wildcard
select fx_user(:'graceUserID', jsonb_build_object(
    'company', '100% Compilers',
    'name', 'Grace Hopper',
    'title', 'Rear Admiral',
    'username', 'grace-h'
));

-- Respondent without name or title
select fx_user(:'linusUserID', jsonb_build_object(
    'company', '1000 Kernels',
    'username', 'linus-t'
));

-- Respondent of another survey of the event
select fx_user(:'otherSurveyUserID', jsonb_build_object('username', 'other-respondent'));

-- Event category used by the surveyed event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the surveyed event group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event owning the surveys
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Another survey of the event
insert into event_survey (event_survey_id, anonymous, event_id, status, title)
values (:'otherSurveyID', false, :'eventID', 'ready', 'Other feedback');

-- Survey whose respondents are searched
insert into event_survey (event_survey_id, anonymous, event_id, status, title)
values (:'surveyID', false, :'eventID', 'ready', 'Feedback');

-- Responses to the searched survey, in creation order
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values
    ('{"answers": []}'::jsonb, '2025-01-02 09:00:00+00', :'surveyID', :'adaUserID'),
    ('{"answers": []}'::jsonb, '2025-01-02 09:01:00+00', :'surveyID', :'graceUserID'),
    ('{"answers": []}'::jsonb, '2025-01-02 09:02:00+00', :'surveyID', :'linusUserID');

-- Response to another survey of the event
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values ('{"answers": []}'::jsonb, '2025-01-02 08:00:00+00', :'otherSurveyID', :'otherSurveyUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return every respondent with its response creation date
select results_eq(
    format(
        $$
            select r.created_at, r.user_id
            from event_survey_matching_respondents(%L::uuid, '{}'::jsonb) r
            order by r.created_at, r.user_id
        $$,
        :'surveyID'
    ),
    format(
        $$
            values
                ('2025-01-02 09:00:00+00'::timestamptz, %L::uuid),
                ('2025-01-02 09:01:00+00'::timestamptz, %L::uuid),
                ('2025-01-02 09:02:00+00'::timestamptz, %L::uuid)
        $$,
        :'adaUserID',
        :'graceUserID',
        :'linusUserID'
    ),
    'Should return every respondent with its response creation date'
);

-- Should match the search literally
select is(
    (
        select jsonb_agg(r.user_id order by r.created_at, r.user_id)
        from event_survey_matching_respondents(:'surveyID'::uuid, '{"ts_query": "100%"}'::jsonb) r
    ),
    jsonb_build_array(:'graceUserID'::uuid),
    'Should match the search literally'
);

-- Should not search respondent emails
select is(
    (
        select count(*)::int
        from event_survey_matching_respondents(:'surveyID'::uuid, '{"ts_query": "ada.mail"}'::jsonb) r
    ),
    0,
    'Should not search respondent emails'
);

-- Should only return responses to the requested survey
select is(
    (
        select jsonb_agg(r.user_id order by r.created_at, r.user_id)
        from event_survey_matching_respondents(:'otherSurveyID'::uuid, '{}'::jsonb) r
    ),
    jsonb_build_array(:'otherSurveyUserID'::uuid),
    'Should only return responses to the requested survey'
);

-- Should search respondents by name, username, company or title
select is(
    (
        select jsonb_object_agg(
            search.term,
            (
                select coalesce(jsonb_agg(r.user_id order by r.created_at, r.user_id), '[]'::jsonb)
                from event_survey_matching_respondents(
                    :'surveyID'::uuid,
                    jsonb_build_object('ts_query', search.term)
                ) r
            )
        )
        from (values ('admiral'), ('grace-h'), ('kernels'), ('LOVELACE')) as search(term)
    ),
    jsonb_build_object(
        'LOVELACE', jsonb_build_array(:'adaUserID'::uuid),
        'admiral', jsonb_build_array(:'graceUserID'::uuid),
        'grace-h', jsonb_build_array(:'graceUserID'::uuid),
        'kernels', jsonb_build_array(:'linusUserID'::uuid)
    ),
    'Should search respondents by name, username, company or title'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
