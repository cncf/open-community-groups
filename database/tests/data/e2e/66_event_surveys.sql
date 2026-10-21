-- E2E seed: event surveys.
-- Depends on: 20_groups.sql (groups), 30_events.sql (event categories),
-- 40_users_badges.sql (users) and 65_event_analytics.sql (analytics event).

-- ============================================================================
-- EVENT SURVEYS
-- ============================================================================

-- Past test event whose surveys cover every state; a test event keeps it out of
-- public listings, statistics and survey emails
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, published_at, test_event, starts_at,
    ends_at
) values (
    '55555555-5555-5555-5555-555555555971',
    'Survey Feedback Event',
    'alpha-survey-feedback',
    'Past event used for event survey coverage.',
    'Europe/Madrid',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() - interval '20 days',
    true,
    now() - interval '3 days',
    now() - interval '3 days' + interval '2 hours'
);

-- Free ticket type of the survey event
insert into event_ticket_type (
    event_ticket_type_id, active, event_id, "order", seats_total, title
) values (
    '56555555-5555-5555-5555-555555555971',
    true,
    '55555555-5555-5555-5555-555555555971',
    1,
    50,
    'General admission'
);

-- Free price window of the survey event ticket type
insert into event_ticket_price_window (
    event_ticket_price_window_id, amount_minor, event_ticket_type_id
) values (
    '57555555-5555-5555-5555-555555555971',
    0,
    '56555555-5555-5555-5555-555555555971'
);

-- Survey respondents and an attendee who did not check in
insert into "user" (
    user_id, username, email, email_verified, name, company, title, auth_hash
) values (
    '77777777-7777-7777-7777-777777777971',
    'e2e-survey-attendee-1',
    'e2e-survey-attendee-1@example.com',
    true,
    'E2E Survey Attendee One',
    'Survey Labs',
    'Platform Engineer',
    'd1e2f3a4b5c6d1e2f3a4b5c6d1e2f3a4b5c6d1e2f3a4b5c6d1e2f3a4b5c6d971'
), (
    '77777777-7777-7777-7777-777777777972',
    'e2e-survey-attendee-2',
    'e2e-survey-attendee-2@example.com',
    true,
    'E2E Survey Attendee Two',
    null,
    null,
    'd1e2f3a4b5c6d1e2f3a4b5c6d1e2f3a4b5c6d1e2f3a4b5c6d1e2f3a4b5c6d972'
), (
    '77777777-7777-7777-7777-777777777973',
    'e2e-survey-attendee-3',
    'e2e-survey-attendee-3@example.com',
    true,
    'E2E Survey Attendee Three',
    null,
    null,
    'd1e2f3a4b5c6d1e2f3a4b5c6d1e2f3a4b5c6d1e2f3a4b5c6d1e2f3a4b5c6d973'
);

-- Confirmed attendees: the first member and two respondents checked in, the
-- third respondent did not
insert into event_attendee (
    event_id, user_id, checked_in, checked_in_at, created_at
) values (
    '55555555-5555-5555-5555-555555555971',
    '77777777-7777-7777-7777-777777777705',
    true,
    now() - interval '3 days' - interval '5 minutes',
    now() - interval '10 days'
), (
    '55555555-5555-5555-5555-555555555971',
    '77777777-7777-7777-7777-777777777971',
    true,
    now() - interval '3 days' - interval '10 minutes',
    now() - interval '9 days'
), (
    '55555555-5555-5555-5555-555555555971',
    '77777777-7777-7777-7777-777777777972',
    true,
    now() - interval '3 days' + interval '5 minutes',
    now() - interval '8 days'
), (
    '55555555-5555-5555-5555-555555555971',
    '77777777-7777-7777-7777-777777777973',
    false,
    null,
    now() - interval '7 days'
);

-- Free ticket of the first survey respondent, shown in the survey respondents
insert into event_purchase (
    event_purchase_id, amount_minor, completed_at, discount_amount_minor,
    event_id, event_ticket_type_id, status, ticket_title, user_id
) values (
    '58555555-5555-5555-5555-555555555971',
    0,
    now() - interval '9 days',
    0,
    '55555555-5555-5555-5555-555555555971',
    '56555555-5555-5555-5555-555555555971',
    'completed',
    'General admission',
    '77777777-7777-7777-7777-777777777971'
);

-- Open identified survey the first member has not answered yet
insert into event_survey (
    event_survey_id, anonymous, audience, created_at, event_id, questions,
    revision, status, title, closes_at, created_by, description,
    first_response_at, open_notification_processed_at,
    open_notification_recipients, updated_at
) values (
    '5c555555-5555-5555-5555-555555555971',
    false,
    'confirmed',
    now() - interval '5 days',
    '55555555-5555-5555-5555-555555555971',
    '[{"id": "5d555555-5555-5555-5555-555555555971", "kind": "free-text", "prompt": "What should we improve?", "required": false, "options": []}, {"id": "5d555555-5555-5555-5555-555555555972", "kind": "single-select", "prompt": "How would you rate the sessions?", "required": true, "options": [{"id": "5e555555-5555-5555-5555-555555555971", "label": "Excellent"}, {"id": "5e555555-5555-5555-5555-555555555972", "label": "Good"}, {"id": "5e555555-5555-5555-5555-555555555973", "label": "Fair"}]}, {"id": "5d555555-5555-5555-5555-555555555973", "kind": "multi-select", "prompt": "Which topics should we cover next?", "required": false, "options": [{"id": "5e555555-5555-5555-5555-555555555974", "label": "Kubernetes"}, {"id": "5e555555-5555-5555-5555-555555555975", "label": "Observability"}, {"id": "5e555555-5555-5555-5555-555555555976", "label": "Security"}]}]'::jsonb,
    2,
    'ready',
    'Session feedback',
    now() + interval '7 days',
    '77777777-7777-7777-7777-777777777703',
    'Tell us how the sessions went so we can plan the next event.',
    now() - interval '2 days',
    now() - interval '3 days' + interval '2 hours',
    4,
    now() - interval '4 days'
);

-- Open anonymous survey for checked-in attendees, already answered by the
-- first member
insert into event_survey (
    event_survey_id, anonymous, audience, created_at, event_id, questions,
    revision, status, title, first_response_at,
    open_notification_processed_at, open_notification_recipients
) values (
    '5c555555-5555-5555-5555-555555555972',
    true,
    'checked-in',
    now() - interval '5 days' + interval '1 hour',
    '55555555-5555-5555-5555-555555555971',
    '[{"id": "5d555555-5555-5555-5555-555555555974", "kind": "single-select", "prompt": "Was the venue easy to reach?", "required": true, "options": [{"id": "5e555555-5555-5555-5555-555555555977", "label": "Yes"}, {"id": "5e555555-5555-5555-5555-555555555978", "label": "No"}]}, {"id": "5d555555-5555-5555-5555-555555555975", "kind": "free-text", "prompt": "Any other comments?", "required": false, "options": []}]'::jsonb,
    2,
    'ready',
    'Venue feedback',
    now() - interval '2 days',
    now() - interval '3 days' + interval '2 hours',
    3
);

-- Draft survey still being prepared
insert into event_survey (
    event_survey_id, created_at, event_id, questions, title, created_by
) values (
    '5c555555-5555-5555-5555-555555555973',
    now() - interval '5 days' + interval '2 hours',
    '55555555-5555-5555-5555-555555555971',
    '[{"id": "5d555555-5555-5555-5555-555555555976", "kind": "free-text", "prompt": "Which speakers would you like to see?", "required": false, "options": []}]'::jsonb,
    'Speaker ideas',
    '77777777-7777-7777-7777-777777777703'
);

-- Ready survey scheduled to open in a few days
insert into event_survey (
    event_survey_id, created_at, event_id, questions, revision, status, title,
    opens_at
) values (
    '5c555555-5555-5555-5555-555555555974',
    now() - interval '5 days' + interval '3 hours',
    '55555555-5555-5555-5555-555555555971',
    '[{"id": "5d555555-5555-5555-5555-555555555977", "kind": "single-select", "prompt": "Would you attend again?", "required": true, "options": [{"id": "5e555555-5555-5555-5555-555555555979", "label": "Yes"}, {"id": "5e555555-5555-5555-5555-555555555980", "label": "No"}]}]'::jsonb,
    2,
    'ready',
    'Follow-up survey',
    now() + interval '5 days'
);

-- Identified survey closed manually after receiving a response
insert into event_survey (
    event_survey_id, anonymous, created_at, event_id, questions, revision,
    status, title, closed_at, first_response_at,
    open_notification_processed_at, open_notification_recipients
) values (
    '5c555555-5555-5555-5555-555555555975',
    false,
    now() - interval '5 days' + interval '4 hours',
    '55555555-5555-5555-5555-555555555971',
    '[{"id": "5d555555-5555-5555-5555-555555555978", "kind": "free-text", "prompt": "First impressions?", "required": false, "options": []}]'::jsonb,
    3,
    'ready',
    'Early feedback',
    now() - interval '1 day',
    now() - interval '2 days' - interval '12 hours',
    now() - interval '3 days' + interval '2 hours',
    4
);

-- Responses to the open identified survey
insert into event_survey_response (
    event_survey_id, user_id, answers, created_at, updated_at
) values (
    '5c555555-5555-5555-5555-555555555971',
    '77777777-7777-7777-7777-777777777971',
    '{"answers": [{"question_id": "5d555555-5555-5555-5555-555555555971", "value": "More time for questions after each talk."}, {"question_id": "5d555555-5555-5555-5555-555555555972", "value": "5e555555-5555-5555-5555-555555555971"}, {"question_id": "5d555555-5555-5555-5555-555555555973", "value": ["5e555555-5555-5555-5555-555555555974", "5e555555-5555-5555-5555-555555555975"]}]}'::jsonb,
    now() - interval '2 days',
    now() - interval '1 day'
), (
    '5c555555-5555-5555-5555-555555555971',
    '77777777-7777-7777-7777-777777777972',
    '{"answers": [{"question_id": "5d555555-5555-5555-5555-555555555971", "value": "A longer networking break."}, {"question_id": "5d555555-5555-5555-5555-555555555972", "value": "5e555555-5555-5555-5555-555555555972"}, {"question_id": "5d555555-5555-5555-5555-555555555973", "value": ["5e555555-5555-5555-5555-555555555976"]}]}'::jsonb,
    now() - interval '2 days' + interval '1 hour',
    null
);

-- Responses to the open anonymous survey, including the first member's
insert into event_survey_response (
    event_survey_id, user_id, answers, created_at, updated_at
) values (
    '5c555555-5555-5555-5555-555555555972',
    '77777777-7777-7777-7777-777777777705',
    '{"answers": [{"question_id": "5d555555-5555-5555-5555-555555555974", "value": "5e555555-5555-5555-5555-555555555977"}, {"question_id": "5d555555-5555-5555-5555-555555555975", "value": "Great venue, thanks!"}]}'::jsonb,
    now() - interval '2 days',
    null
), (
    '5c555555-5555-5555-5555-555555555972',
    '77777777-7777-7777-7777-777777777971',
    '{"answers": [{"question_id": "5d555555-5555-5555-5555-555555555974", "value": "5e555555-5555-5555-5555-555555555977"}]}'::jsonb,
    now() - interval '2 days' + interval '2 hours',
    null
), (
    '5c555555-5555-5555-5555-555555555972',
    '77777777-7777-7777-7777-777777777972',
    '{"answers": [{"question_id": "5d555555-5555-5555-5555-555555555974", "value": "5e555555-5555-5555-5555-555555555978"}, {"question_id": "5d555555-5555-5555-5555-555555555975", "value": "Hard to find the entrance."}]}'::jsonb,
    now() - interval '2 days' + interval '3 hours',
    null
);

-- Response to the closed identified survey
insert into event_survey_response (
    event_survey_id, user_id, answers, created_at, updated_at
) values (
    '5c555555-5555-5555-5555-555555555975',
    '77777777-7777-7777-7777-777777777971',
    '{"answers": [{"question_id": "5d555555-5555-5555-5555-555555555978", "value": "Well organized."}]}'::jsonb,
    now() - interval '2 days' - interval '12 hours',
    null
);

-- ============================================================================
-- EVENT ANALYTICS SURVEYS
-- ============================================================================

-- Open survey of the past analytics event, answered by one attendee and by a
-- user who never attended
insert into event_survey (
    event_survey_id, created_at, event_id, questions, revision, status, title,
    first_response_at, open_notification_processed_at,
    open_notification_recipients
) values (
    '5c555555-5555-5555-5555-555555555961',
    now() - interval '5 days',
    '55555555-5555-5555-5555-555555555961',
    '[{"id": "5d555555-5555-5555-5555-555555555961", "kind": "free-text", "prompt": "What did you enjoy most?", "required": false, "options": []}]'::jsonb,
    2,
    'ready',
    'Analytics session survey',
    now() - interval '2 days',
    now() - interval '3 days' + interval '2 hours',
    2
);

-- Survey of the past analytics event for checked-in attendees, closed after
-- both of them answered
insert into event_survey (
    event_survey_id, audience, created_at, event_id, questions, revision,
    status, title, closed_at, first_response_at,
    open_notification_processed_at, open_notification_recipients
) values (
    '5c555555-5555-5555-5555-555555555962',
    'checked-in',
    now() - interval '5 days' + interval '1 hour',
    '55555555-5555-5555-5555-555555555961',
    '[{"id": "5d555555-5555-5555-5555-555555555962", "kind": "single-select", "prompt": "Was the venue easy to reach?", "required": true, "options": [{"id": "5e555555-5555-5555-5555-555555555961", "label": "Yes"}, {"id": "5e555555-5555-5555-5555-555555555962", "label": "No"}]}]'::jsonb,
    3,
    'ready',
    'Analytics venue survey',
    now() - interval '1 day',
    now() - interval '2 days',
    now() - interval '3 days' + interval '2 hours',
    2
);

-- Survey of the past analytics event scheduled to open in a few days
insert into event_survey (
    event_survey_id, created_at, event_id, questions, revision, status, title,
    opens_at
) values (
    '5c555555-5555-5555-5555-555555555963',
    now() - interval '5 days' + interval '2 hours',
    '55555555-5555-5555-5555-555555555961',
    '[{"id": "5d555555-5555-5555-5555-555555555963", "kind": "free-text", "prompt": "Anything else?", "required": false, "options": []}]'::jsonb,
    2,
    'ready',
    'Analytics follow-up survey',
    now() + interval '5 days'
);

-- Draft survey of the past analytics event left out of the analytics
insert into event_survey (
    event_survey_id, created_at, event_id, questions, title
) values (
    '5c555555-5555-5555-5555-555555555964',
    now() - interval '5 days' + interval '3 hours',
    '55555555-5555-5555-5555-555555555961',
    '[{"id": "5d555555-5555-5555-5555-555555555964", "kind": "free-text", "prompt": "Ideas for next time?", "required": false, "options": []}]'::jsonb,
    'Analytics draft survey'
);

-- Responses to the open analytics survey from an attendee and a non-attendee
insert into event_survey_response (
    event_survey_id, user_id, answers, created_at
) values (
    '5c555555-5555-5555-5555-555555555961',
    '77777777-7777-7777-7777-777777777961',
    '{"answers": [{"question_id": "5d555555-5555-5555-5555-555555555961", "value": "The hands-on workshop."}]}'::jsonb,
    now() - interval '2 days'
), (
    '5c555555-5555-5555-5555-555555555961',
    '77777777-7777-7777-7777-777777777973',
    '{"answers": [{"question_id": "5d555555-5555-5555-5555-555555555961", "value": "The recordings."}]}'::jsonb,
    now() - interval '2 days' + interval '1 hour'
);

-- Responses to the closed analytics survey from both checked-in attendees
insert into event_survey_response (
    event_survey_id, user_id, answers, created_at
) values (
    '5c555555-5555-5555-5555-555555555962',
    '77777777-7777-7777-7777-777777777961',
    '{"answers": [{"question_id": "5d555555-5555-5555-5555-555555555962", "value": "5e555555-5555-5555-5555-555555555961"}]}'::jsonb,
    now() - interval '2 days'
), (
    '5c555555-5555-5555-5555-555555555962',
    '77777777-7777-7777-7777-777777777962',
    '{"answers": [{"question_id": "5d555555-5555-5555-5555-555555555962", "value": "5e555555-5555-5555-5555-555555555962"}]}'::jsonb,
    now() - interval '2 days' + interval '1 hour'
);
