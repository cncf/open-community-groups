-- Tests rejecting requests prepared for another revision of a survey.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'a5e00040-0000-0000-0000-000000000001'
\set eventCategoryID 'a5e00040-0000-0000-0000-000000000002'
\set eventID 'a5e00040-0000-0000-0000-000000000003'
\set groupCategoryID 'a5e00040-0000-0000-0000-000000000004'
\set groupID 'a5e00040-0000-0000-0000-000000000005'
\set surveyID 'a5e00040-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed event
select fx_community(:'communityID');

-- Event category used by the surveyed event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the surveyed event group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event owning the survey
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Survey at its third revision
insert into event_survey (event_survey_id, event_id, revision, title)
values (:'surveyID', :'eventID', 3, 'Feedback');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept the current revision
select lives_ok(
    format(
        $$
            select validate_event_survey_revision(
                (select s from event_survey s where s.event_survey_id = %L::uuid),
                3
            )
        $$,
        :'surveyID'
    ),
    'Should accept the current revision'
);

-- Should reject missing revisions
select throws_ok(
    format(
        $$
            select validate_event_survey_revision(
                (select s from event_survey s where s.event_survey_id = %L::uuid),
                null
            )
        $$,
        :'surveyID'
    ),
    'OCG01',
    'the survey changed; review and try again',
    'Should reject missing revisions'
);

-- Should reject revisions ahead of the survey
select throws_ok(
    format(
        $$
            select validate_event_survey_revision(
                (select s from event_survey s where s.event_survey_id = %L::uuid),
                4
            )
        $$,
        :'surveyID'
    ),
    'OCG01',
    'the survey changed; review and try again',
    'Should reject revisions ahead of the survey'
);

-- Should reject stale revisions
select throws_ok(
    format(
        $$
            select validate_event_survey_revision(
                (select s from event_survey s where s.event_survey_id = %L::uuid),
                2
            )
        $$,
        :'surveyID'
    ),
    'OCG01',
    'the survey changed; review and try again',
    'Should reject stale revisions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
