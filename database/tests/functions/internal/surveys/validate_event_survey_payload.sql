-- Tests validating and resolving survey configuration payloads.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(29);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'a5e00008-0000-0000-0000-000000000001'
\set eventCategoryID 'a5e00008-0000-0000-0000-000000000002'
\set eventID 'a5e00008-0000-0000-0000-000000000003'
\set groupCategoryID 'a5e00008-0000-0000-0000-000000000004'
\set groupID 'a5e00008-0000-0000-0000-000000000005'
\set payload '{"anonymous": false, "audience": "checked-in", "closes_at": "2030-06-02T10:00:00", "description": "  Tell us how it went  ", "opens_at": "2030-06-01T10:00:00", "questions": [{"id": "a5e00008-0000-0000-0000-000000000006", "kind": "free-text", "prompt": "Feedback", "required": true}], "title": "  Event feedback  "}'

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

-- Event whose timezone interprets the survey dates
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'timezone', 'Europe/Madrid'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept closing dates without an opening date
select lives_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb - 'opens_at')
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'Should accept closing dates without an opening date'
);

-- Should accept descriptions at the length limit
select lives_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || jsonb_build_object('description', repeat('d', 500)))
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'Should accept descriptions at the length limit'
);

-- Should accept drafts without questions
select is(
    (
        select v.questions
        from event e
        cross join lateral validate_event_survey_payload(
            e,
            :'payload'::jsonb || '{"questions": []}'::jsonb
        ) v
        where e.event_id = :'eventID'
    ),
    '[]'::jsonb,
    'Should accept drafts without questions'
);

-- Should accept the question limit
select lives_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || jsonb_build_object(
                'questions', (
                    select jsonb_agg(jsonb_build_object(
                        'id', gen_random_uuid(),
                        'kind', 'free-text',
                        'prompt', 'Question',
                        'required', false
                    ))
                    from generate_series(1, 30)
                )
            ))
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'Should accept the question limit'
);

-- Should accept titles at the length limit after trimming
select lives_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || jsonb_build_object('title', '  ' || repeat('t', 120) || '  '))
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'Should accept titles at the length limit after trimming'
);

-- Should normalize blank descriptions to null
select is(
    (
        select v.description
        from event e
        cross join lateral validate_event_survey_payload(
            e,
            :'payload'::jsonb || '{"description": "   "}'::jsonb
        ) v
        where e.event_id = :'eventID'
    ),
    null::text,
    'Should normalize blank descriptions to null'
);

-- Should reject blank titles
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || '{"title": "   "}'::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey title is required',
    'Should reject blank titles'
);

-- Should reject closing dates before the opening date
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || '{"closes_at": "2030-05-31T10:00:00"}'::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey closing date must be after the opening date',
    'Should reject closing dates before the opening date'
);

-- Should reject closing dates equal to the opening date
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || '{"closes_at": "2030-06-01T10:00:00"}'::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey closing date must be after the opening date',
    'Should reject closing dates equal to the opening date'
);

-- Should reject descriptions longer than the limit
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || jsonb_build_object('description', repeat('d', 501)))
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey description is too long',
    'Should reject descriptions longer than the limit'
);

-- Should reject invalid dates
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || '{"opens_at": "not-a-date"}'::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey dates are invalid',
    'Should reject invalid dates'
);

-- Should reject invalid question definitions
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || '{"questions": [{"kind": "free-text"}]}'::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'questionnaire question id must be a uuid',
    'Should reject invalid question definitions'
);

-- Should reject missing anonymous flags
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb - 'anonymous')
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey anonymous flag must be a boolean',
    'Should reject missing anonymous flags'
);

-- Should reject missing audiences
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb - 'audience')
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey audience is invalid',
    'Should reject missing audiences'
);

-- Should reject missing questions
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb - 'questions')
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'questionnaire questions must be an array',
    'Should reject missing questions'
);

-- Should reject missing titles
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb - 'title')
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey title is required',
    'Should reject missing titles'
);

-- Should reject more questions than the limit
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || jsonb_build_object(
                'questions', (
                    select jsonb_agg(jsonb_build_object(
                        'id', gen_random_uuid(),
                        'kind', 'free-text',
                        'prompt', 'Question',
                        'required', false
                    ))
                    from generate_series(1, 31)
                )
            ))
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'surveys can have up to 30 questions',
    'Should reject more questions than the limit'
);

-- Should reject non-boolean anonymous flags
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || '{"anonymous": "yes"}'::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey anonymous flag must be a boolean',
    'Should reject non-boolean anonymous flags'
);

-- Should reject non-object payloads
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, '[]'::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'eventID'
    ),
    'OCG01',
    'event survey payload must be an object',
    'Should reject non-object payloads'
);

-- Should reject non-string audiences
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || '{"audience": 5}'::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey audience is invalid',
    'Should reject non-string audiences'
);

-- Should reject non-string descriptions
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || '{"description": 5}'::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey description must be a string',
    'Should reject non-string descriptions'
);

-- Should reject non-string titles
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || '{"title": 5}'::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey title is required',
    'Should reject non-string titles'
);

-- Should reject null payloads
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, null::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'eventID'
    ),
    'OCG01',
    'event survey payload must be an object',
    'Should reject null payloads'
);

-- Should reject out-of-range dates
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || '{"opens_at": "2030-13-01T10:00:00"}'::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey dates are invalid',
    'Should reject out-of-range dates'
);

-- Should reject titles longer than the limit
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || jsonb_build_object('title', repeat('t', 121)))
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey title is too long',
    'Should reject titles longer than the limit'
);

-- Should reject unknown audiences
select throws_ok(
    format(
        $$
            select validate_event_survey_payload(e, %L::jsonb || '{"audience": "everyone"}'::jsonb)
            from event e
            where e.event_id = %L::uuid
        $$,
        :'payload',
        :'eventID'
    ),
    'OCG01',
    'event survey audience is invalid',
    'Should reject unknown audiences'
);

-- Should resolve absent optional settings to null
select results_eq(
    format(
        $$
            select closes_at, description, opens_at
            from validate_event_survey_payload(
                (select e from event e where e.event_id = %L::uuid),
                %L::jsonb - 'closes_at' - 'description' - 'opens_at'
            )
        $$,
        :'eventID',
        :'payload'
    ),
    $$ values (null::timestamptz, null::text, null::timestamptz) $$,
    'Should resolve absent optional settings to null'
);

-- Should resolve null optional settings to null
select results_eq(
    format(
        $$
            select closes_at, description, opens_at
            from validate_event_survey_payload(
                (select e from event e where e.event_id = %L::uuid),
                %L::jsonb || '{"closes_at": null, "description": null, "opens_at": null}'::jsonb
            )
        $$,
        :'eventID',
        :'payload'
    ),
    $$ values (null::timestamptz, null::text, null::timestamptz) $$,
    'Should resolve null optional settings to null'
);

-- Should resolve the survey settings with dates in the event timezone
select results_eq(
    format(
        $$
            select anonymous, audience, closes_at, description, opens_at, questions, title
            from validate_event_survey_payload(
                (select e from event e where e.event_id = %L::uuid),
                %L::jsonb
            )
        $$,
        :'eventID',
        :'payload'
    ),
    $$ values (
        false,
        'checked-in'::text,
        '2030-06-02 08:00:00+00'::timestamptz,
        'Tell us how it went'::text,
        '2030-06-01 08:00:00+00'::timestamptz,
        '[{"id": "a5e00008-0000-0000-0000-000000000006", "kind": "free-text", "prompt": "Feedback", "required": true}]'::jsonb,
        'Event feedback'::text
    ) $$,
    'Should resolve the survey settings with dates in the event timezone'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
