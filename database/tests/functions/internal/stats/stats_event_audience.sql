-- Tests audience composition and registration answer breakdowns of an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(16);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID 'ea070000-0000-0000-0000-000000000001'
\set communityID 'ea070000-0000-0000-0000-000000000002'
\set eventCategory2ID 'ea070000-0000-0000-0000-000000000003'
\set eventCategoryID 'ea070000-0000-0000-0000-000000000004'
\set eventID 'ea070000-0000-0000-0000-000000000005'
\set eventLaterID 'ea070000-0000-0000-0000-000000000006'
\set eventPriorCanceledID 'ea070000-0000-0000-0000-000000000007'
\set eventPriorDeletedID 'ea070000-0000-0000-0000-000000000008'
\set eventPriorID 'ea070000-0000-0000-0000-000000000009'
\set eventPriorOtherGroupID 'ea070000-0000-0000-0000-00000000000a'
\set eventPriorTestID 'ea070000-0000-0000-0000-00000000000b'
\set group2ID 'ea070000-0000-0000-0000-00000000000c'
\set groupCategory2ID 'ea070000-0000-0000-0000-00000000000d'
\set groupCategoryID 'ea070000-0000-0000-0000-00000000000e'
\set groupID 'ea070000-0000-0000-0000-00000000000f'
\set member1ID 'ea070000-0000-0000-0000-000000000010'
\set member2ID 'ea070000-0000-0000-0000-000000000011'
\set member3ID 'ea070000-0000-0000-0000-000000000012'
\set member4ID 'ea070000-0000-0000-0000-000000000013'
\set member5ID 'ea070000-0000-0000-0000-000000000014'
\set option1ID 'ea070000-0000-0000-0000-000000000015'
\set option2ID 'ea070000-0000-0000-0000-000000000016'
\set option3ID 'ea070000-0000-0000-0000-000000000017'
\set option4ID 'ea070000-0000-0000-0000-000000000018'
\set option5ID 'ea070000-0000-0000-0000-000000000019'
\set option6ID 'ea070000-0000-0000-0000-00000000001a'
\set option7ID 'ea070000-0000-0000-0000-00000000001b'
\set question1ID 'ea070000-0000-0000-0000-00000000001c'
\set question2ID 'ea070000-0000-0000-0000-00000000001d'
\set question3ID 'ea070000-0000-0000-0000-00000000001e'
\set question4ID 'ea070000-0000-0000-0000-00000000001f'
\set userCanceledPriorID 'ea070000-0000-0000-0000-000000000020'
\set userCanceledTargetID 'ea070000-0000-0000-0000-000000000021'
\set userDeletedPriorID 'ea070000-0000-0000-0000-000000000022'
\set userLaterOnlyID 'ea070000-0000-0000-0000-000000000023'
\set userNotConfirmedPriorID 'ea070000-0000-0000-0000-000000000024'
\set userOtherGroupID 'ea070000-0000-0000-0000-000000000025'
\set userReturningID 'ea070000-0000-0000-0000-000000000026'
\set userTestPriorID 'ea070000-0000-0000-0000-000000000027'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, categories and groups
select fx_community(:'communityID');
select fx_community(:'community2ID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group_category(:'groupCategory2ID', :'community2ID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_event_category(:'eventCategory2ID', :'community2ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'group2ID', :'community2ID', :'groupCategory2ID');

-- Members joining across the registration timeline and prior attendees
select fx_user(:'member1ID');
select fx_user(:'member2ID');
select fx_user(:'member3ID');
select fx_user(:'member4ID');
select fx_user(:'member5ID');
select fx_user(:'userCanceledPriorID');
select fx_user(:'userCanceledTargetID');
select fx_user(:'userDeletedPriorID');
select fx_user(:'userLaterOnlyID');
select fx_user(:'userNotConfirmedPriorID');
select fx_user(:'userOtherGroupID');
select fx_user(:'userReturningID');
select fx_user(:'userTestPriorID');

-- Ended event with registration bounds and select questions
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '4 days',
    'published', true,
    'published_at', current_timestamp - interval '30 days',
    'registration_ends_at', current_timestamp - interval '10 days',
    'registration_questions', jsonb_build_array(
        jsonb_build_object(
            'id', :'question1ID',
            'kind', 'single-select',
            'options', jsonb_build_array(
                jsonb_build_object('id', :'option1ID', 'label', 'Dev'),
                jsonb_build_object('id', :'option2ID', 'label', 'Ops')
            ),
            'prompt', 'Role',
            'required', false
        ),
        jsonb_build_object(
            'id', :'question2ID',
            'kind', 'free-text',
            'options', jsonb_build_array(),
            'prompt', 'Comments',
            'required', false
        ),
        jsonb_build_object(
            'id', :'question3ID',
            'kind', 'multi-select',
            'options', jsonb_build_array(
                jsonb_build_object('id', :'option4ID', 'label', 'AI'),
                jsonb_build_object('id', :'option5ID', 'label', 'Cloud'),
                jsonb_build_object('id', :'option6ID', 'label', 'Data')
            ),
            'prompt', 'Interests',
            'required', false
        ),
        jsonb_build_object(
            'id', :'question4ID',
            'kind', 'single-select',
            'options', jsonb_build_array(
                jsonb_build_object('id', :'option7ID', 'label', 'Yes')
            ),
            'prompt', 'Unanswered',
            'required', false
        )
    ),
    'registration_starts_at', current_timestamp - interval '20 days',
    'starts_at', current_timestamp - interval '5 days'
));

-- Later event of the same group
select fx_event(:'eventLaterID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', current_timestamp + interval '10 days'
));

-- Prior event of the same group
select fx_event(:'eventPriorID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', current_timestamp - interval '60 days'
));

-- Prior canceled event of the same group
select fx_event(:'eventPriorCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'starts_at', current_timestamp - interval '60 days'
));

-- Prior deleted event of the same group
select fx_event(:'eventPriorDeletedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'deleted_at', current_timestamp - interval '50 days',
    'starts_at', current_timestamp - interval '60 days'
));

-- Prior event of another group
select fx_event(:'eventPriorOtherGroupID', :'group2ID', :'eventCategory2ID', jsonb_build_object(
    'starts_at', current_timestamp - interval '60 days'
));

-- Prior test event of the same group
select fx_event(:'eventPriorTestID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', current_timestamp - interval '60 days',
    'test_event', true
));

-- Attendances at the analyzed event, with select answers including a removed option and a non-option value
insert into event_attendee (event_id, user_id, status, attendance_canceled_at, registration_answers) values
    (:'eventID', :'member2ID', 'confirmed', null, jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object('question_id', :'question1ID', 'value', :'option1ID'),
        jsonb_build_object('question_id', :'question2ID', 'value', 'Free text answer'),
        jsonb_build_object('question_id', :'question3ID', 'value', jsonb_build_array(:'option4ID', :'option5ID'))
    ))),
    (:'eventID', :'member4ID', 'confirmed', null, jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object('question_id', :'question1ID', 'value', :'option3ID'),
        jsonb_build_object('question_id', :'question3ID', 'value', jsonb_build_array(:'option4ID', 'Not an option')),
        jsonb_build_object('question_id', :'question4ID', 'value', 'Free text kept from an earlier question kind')
    ))),
    (:'eventID', :'userCanceledPriorID', 'confirmed', null, null),
    (:'eventID', :'userCanceledTargetID', 'attendance-canceled', current_timestamp - interval '6 days', jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object('question_id', :'question1ID', 'value', :'option1ID')
    ))),
    (:'eventID', :'userDeletedPriorID', 'confirmed', null, null),
    (:'eventID', :'userLaterOnlyID', 'confirmed', null, null),
    (:'eventID', :'userNotConfirmedPriorID', 'confirmed', null, null),
    (:'eventID', :'userOtherGroupID', 'confirmed', null, null),
    (:'eventID', :'userReturningID', 'confirmed', null, jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object('question_id', :'question1ID', 'value', :'option2ID'),
        jsonb_build_object('question_id', :'question3ID', 'value', jsonb_build_array())
    ))),
    (:'eventID', :'userTestPriorID', 'confirmed', null, null);

-- Attendances at other events deciding whether attendees return
insert into event_attendee (event_id, user_id, status, attendance_canceled_at) values
    (:'eventLaterID', :'userLaterOnlyID', 'confirmed', null),
    (:'eventPriorCanceledID', :'userCanceledPriorID', 'confirmed', null),
    (:'eventPriorDeletedID', :'userDeletedPriorID', 'confirmed', null),
    (:'eventPriorID', :'userCanceledTargetID', 'confirmed', null),
    (:'eventPriorID', :'userNotConfirmedPriorID', 'attendance-canceled', current_timestamp - interval '61 days'),
    (:'eventPriorID', :'userReturningID', 'confirmed', null),
    (:'eventPriorOtherGroupID', :'userOtherGroupID', 'confirmed', null),
    (:'eventPriorTestID', :'userTestPriorID', 'confirmed', null);

-- Group members joining before, during and after the registration window
insert into group_member (group_id, user_id, created_at) values
    (:'groupID', :'member1ID', current_timestamp - interval '25 days'),
    (:'groupID', :'member2ID', current_timestamp - interval '15 days'),
    (:'groupID', :'member3ID', current_timestamp - interval '7 days'),
    (:'groupID', :'member4ID', current_timestamp - interval '4 days 12 hours'),
    (:'groupID', :'member5ID', current_timestamp - interval '2 days');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should break down select questions by their current options, ignoring non-option values
select is(
    (select stats_event_audience(e)::jsonb->'questions' from event e where e.event_id = :'eventID'),
    jsonb_build_array(
        jsonb_build_object(
            'kind', 'single-select',
            'options', jsonb_build_array(
                jsonb_build_object('count', 1, 'label', 'Dev', 'option_id', :'option1ID'),
                jsonb_build_object('count', 1, 'label', 'Ops', 'option_id', :'option2ID')
            ),
            'prompt', 'Role',
            'question_id', :'question1ID',
            'respondents', 2,
            'selections', 2
        ),
        jsonb_build_object(
            'kind', 'multi-select',
            'options', jsonb_build_array(
                jsonb_build_object('count', 2, 'label', 'AI', 'option_id', :'option4ID'),
                jsonb_build_object('count', 1, 'label', 'Cloud', 'option_id', :'option5ID'),
                jsonb_build_object('count', 0, 'label', 'Data', 'option_id', :'option6ID')
            ),
            'prompt', 'Interests',
            'question_id', :'question3ID',
            'respondents', 2,
            'selections', 3
        ),
        jsonb_build_object(
            'kind', 'single-select',
            'options', jsonb_build_array(
                jsonb_build_object('count', 0, 'label', 'Yes', 'option_id', :'option7ID')
            ),
            'prompt', 'Unanswered',
            'question_id', :'question4ID',
            'respondents', 0,
            'selections', 0
        )
    ),
    'Should break down select questions by their current options, ignoring non-option values'
);

-- Should cap a registration end after the event end at the effective end
select is(
    (
        select stats_event_audience(
            jsonb_populate_record(e, jsonb_build_object(
                'registration_ends_at', current_timestamp - interval '3 days',
                'registration_starts_at', null
            ))
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', true,
        'window_end_inferred', false,
        'window_start_inferred', true,

        'members_joined_in_window', 4,
        'members_joined_in_window_registered', 2,
        'window_ends_at', epoch_seconds(current_timestamp - interval '4 days'),
        'window_starts_at', epoch_seconds(current_timestamp - interval '30 days')
    ),
    'Should cap a registration end after the event end at the effective end'
);

-- Should cap an open registration window at the observation time
select is(
    (
        select stats_event_audience(
            jsonb_populate_record(e, jsonb_build_object(
                'ends_at', current_timestamp + interval '3 days',
                'registration_ends_at', current_timestamp + interval '1 day',
                'registration_starts_at', null,
                'starts_at', current_timestamp + interval '2 days'
            ))
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', true,
        'window_end_inferred', false,
        'window_start_inferred', true,

        'members_joined_in_window', 5,
        'members_joined_in_window_registered', 2,
        'window_ends_at', epoch_seconds(current_timestamp),
        'window_starts_at', epoch_seconds(current_timestamp - interval '30 days')
    ),
    'Should cap an open registration window at the observation time'
);

-- Should close at the event start when only the registration start is set
select is(
    (
        select stats_event_audience(
            jsonb_populate_record(e, jsonb_build_object(
                'registration_ends_at', null
            ))
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', false,
        'window_end_inferred', false,
        'window_start_inferred', false,

        'members_joined_in_window', 2,
        'members_joined_in_window_registered', 1,
        'window_ends_at', epoch_seconds(current_timestamp - interval '5 days'),
        'window_starts_at', epoch_seconds(current_timestamp - interval '20 days')
    ),
    'Should close at the event start when only the registration start is set'
);

-- Should close ongoing events at the observation time without registration bounds
select is(
    (
        select stats_event_audience(
            jsonb_populate_record(e, jsonb_build_object(
                'ends_at', current_timestamp + interval '1 day',
                'registration_ends_at', null,
                'registration_starts_at', null,
                'starts_at', current_timestamp - interval '1 day'
            ))
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', false,
        'window_end_inferred', true,
        'window_start_inferred', true,

        'members_joined_in_window', 5,
        'members_joined_in_window_registered', 2,
        'window_ends_at', epoch_seconds(current_timestamp),
        'window_starts_at', epoch_seconds(current_timestamp - interval '30 days')
    ),
    'Should close ongoing events at the observation time without registration bounds'
);

-- Should close undated events at the observation time without registration bounds
select is(
    (
        select stats_event_audience(
            jsonb_populate_record(e, jsonb_build_object(
                'ends_at', null,
                'registration_ends_at', null,
                'registration_starts_at', null,
                'starts_at', null
            ))
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', false,
        'window_end_inferred', true,
        'window_start_inferred', true,

        'members_joined_in_window', 5,
        'members_joined_in_window_registered', 2,
        'window_ends_at', epoch_seconds(current_timestamp),
        'window_starts_at', epoch_seconds(current_timestamp - interval '30 days')
    ),
    'Should close undated events at the observation time without registration bounds'
);

-- Should close undated events at the registration end when only it is set
select is(
    (
        select stats_event_audience(
            jsonb_populate_record(e, jsonb_build_object(
                'ends_at', null,
                'registration_starts_at', null,
                'starts_at', null
            ))
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', false,
        'window_end_inferred', false,
        'window_start_inferred', true,

        'members_joined_in_window', 2,
        'members_joined_in_window_registered', 1,
        'window_ends_at', epoch_seconds(current_timestamp - interval '10 days'),
        'window_starts_at', epoch_seconds(current_timestamp - interval '30 days')
    ),
    'Should close undated events at the registration end when only it is set'
);

-- Should keep undated events open with only a registration start
select is(
    (
        select stats_event_audience(
            jsonb_populate_record(e, jsonb_build_object(
                'ends_at', null,
                'registration_ends_at', null,
                'starts_at', null
            ))
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', false,
        'window_end_inferred', true,
        'window_start_inferred', false,

        'members_joined_in_window', 4,
        'members_joined_in_window_registered', 2,
        'window_ends_at', epoch_seconds(current_timestamp),
        'window_starts_at', epoch_seconds(current_timestamp - interval '20 days')
    ),
    'Should keep undated events open with only a registration start'
);

-- Should open at the publication and close at the event end without registration bounds
select is(
    (
        select stats_event_audience(
            jsonb_populate_record(e, jsonb_build_object(
                'registration_ends_at', null,
                'registration_starts_at', null
            ))
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', false,
        'window_end_inferred', true,
        'window_start_inferred', true,

        'members_joined_in_window', 4,
        'members_joined_in_window_registered', 2,
        'window_ends_at', epoch_seconds(current_timestamp - interval '4 days'),
        'window_starts_at', epoch_seconds(current_timestamp - interval '30 days')
    ),
    'Should open at the publication and close at the event end without registration bounds'
);

-- Should open at the publication when only the registration end is set
select is(
    (
        select stats_event_audience(
            jsonb_populate_record(e, jsonb_build_object(
                'registration_starts_at', null
            ))
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', false,
        'window_end_inferred', false,
        'window_start_inferred', true,

        'members_joined_in_window', 2,
        'members_joined_in_window_registered', 1,
        'window_ends_at', epoch_seconds(current_timestamp - interval '10 days'),
        'window_starts_at', epoch_seconds(current_timestamp - interval '30 days')
    ),
    'Should open at the publication when only the registration end is set'
);

-- Should return null membership figures when the window start is not before its end
select is(
    (
        select stats_event_audience(
            jsonb_populate_record(e, jsonb_build_object(
                'published_at', current_timestamp - interval '1 day',
                'registration_ends_at', null,
                'registration_starts_at', null
            ))
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', false,
        'window_end_inferred', true,
        'window_start_inferred', true,

        'members_joined_in_window', null,
        'members_joined_in_window_registered', null,
        'window_ends_at', null,
        'window_starts_at', null
    ),
    'Should return null membership figures when the window start is not before its end'
);

-- Should return null membership figures without a window start
select is(
    (
        select stats_event_audience(
            jsonb_populate_record(e, jsonb_build_object(
                'published_at', null,
                'registration_starts_at', null
            ))
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', false,
        'window_end_inferred', false,
        'window_start_inferred', true,

        'members_joined_in_window', null,
        'members_joined_in_window_registered', null,
        'window_ends_at', null,
        'window_starts_at', null
    ),
    'Should return null membership figures without a window start'
);

-- Should return null new and returning counts for undated events
select is(
    (
        select jsonb_build_object(
            'new_attendees', audience->'new_attendees',
            'returning_attendees', audience->'returning_attendees'
        )
        from (
            select stats_event_audience(
                jsonb_populate_record(e, jsonb_build_object(
                    'ends_at', null,
                    'starts_at', null
                ))
            )::jsonb as audience
            from event e
            where e.event_id = :'eventID'
        ) stats
    ),
    '{"new_attendees": null, "returning_attendees": null}'::jsonb,
    'Should return null new and returning counts for undated events'
);

-- Should split attendees into new and returning by prior same-group attendance
select is(
    (
        select jsonb_build_object(
            'new_attendees', audience->'new_attendees',
            'returning_attendees', audience->'returning_attendees'
        )
        from (
            select stats_event_audience(e)::jsonb as audience
            from event e
            where e.event_id = :'eventID'
        ) stats
    ),
    '{"new_attendees": 8, "returning_attendees": 1}'::jsonb,
    'Should split attendees into new and returning by prior same-group attendance'
);

-- Should use both registration bounds for undated events
select is(
    (
        select stats_event_audience(
            jsonb_populate_record(e, jsonb_build_object(
                'ends_at', null,
                'starts_at', null
            ))
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', false,
        'window_end_inferred', false,
        'window_start_inferred', false,

        'members_joined_in_window', 1,
        'members_joined_in_window_registered', 1,
        'window_ends_at', epoch_seconds(current_timestamp - interval '10 days'),
        'window_starts_at', epoch_seconds(current_timestamp - interval '20 days')
    ),
    'Should use both registration bounds for undated events'
);

-- Should use both registration bounds when set
select is(
    (
        select stats_event_audience(
            e
        )::jsonb - 'new_attendees' - 'questions' - 'returning_attendees'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'window_end_capped', false,
        'window_end_inferred', false,
        'window_start_inferred', false,

        'members_joined_in_window', 1,
        'members_joined_in_window_registered', 1,
        'window_ends_at', epoch_seconds(current_timestamp - interval '10 days'),
        'window_starts_at', epoch_seconds(current_timestamp - interval '20 days')
    ),
    'Should use both registration bounds when set'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
