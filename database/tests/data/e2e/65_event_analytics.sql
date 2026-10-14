-- E2E seed: event analytics.
-- Depends on: 20_groups.sql (groups), 30_events.sql (event categories) and
-- 40_users_badges.sql (users).

-- ============================================================================
-- EVENT ANALYTICS
-- ============================================================================

-- Test events keep the analytics fixtures out of public listings and stats:
-- a past paid event with traffic, attribution and check-ins, and a future free
-- event.
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, payment_currency_code, published, published_at,
    test_event, starts_at, ends_at, registration_questions
) values (
    '55555555-5555-5555-5555-555555555961',
    'Analytics Past Paid Event',
    'alpha-analytics-past-paid',
    'Past paid event used for event analytics coverage.',
    'Europe/Madrid',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    now() - interval '20 days',
    true,
    now() - interval '3 days',
    now() - interval '3 days' + interval '2 hours',
    '[{"id": "5a555555-5555-5555-5555-555555555961", "kind": "single-select", "prompt": "Role", "required": false, "options": [{"id": "5b555555-5555-5555-5555-555555555961", "label": "Developer"}, {"id": "5b555555-5555-5555-5555-555555555962", "label": "Operator"}]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555962',
    'Analytics Future Free Event',
    'alpha-analytics-future-free',
    'Future free event used for event analytics coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    now() - interval '2 days',
    true,
    now() + interval '20 days',
    now() + interval '20 days 2 hours',
    '[]'::jsonb
);

-- Attendees of the past paid analytics event
insert into "user" (
    user_id, username, email, email_verified, name, auth_hash
) values (
    '77777777-7777-7777-7777-777777777961',
    'e2e-analytics-attendee-1',
    'e2e-analytics-attendee-1@example.com',
    true,
    'E2E Analytics Attendee One',
    'c1d2e3f4a5b6c1d2e3f4a5b6c1d2e3f4a5b6c1d2e3f4a5b6c1d2e3f4a5b6c961'
), (
    '77777777-7777-7777-7777-777777777962',
    'e2e-analytics-attendee-2',
    'e2e-analytics-attendee-2@example.com',
    true,
    'E2E Analytics Attendee Two',
    'c1d2e3f4a5b6c1d2e3f4a5b6c1d2e3f4a5b6c1d2e3f4a5b6c1d2e3f4a5b6c962'
);

-- Paid ticket type of the past event and free tier of the future event
insert into event_ticket_type (
    event_ticket_type_id, active, event_id, "order", seats_total, title
) values (
    '56555555-5555-5555-5555-555555555961',
    true,
    '55555555-5555-5555-5555-555555555961',
    1,
    20,
    'Analytics pass'
), (
    '56555555-5555-5555-5555-555555555962',
    true,
    '55555555-5555-5555-5555-555555555962',
    1,
    50,
    'General admission'
);

-- Paid and free price windows of the analytics ticket types
insert into event_ticket_price_window (
    event_ticket_price_window_id, amount_minor, event_ticket_type_id
) values (
    '57555555-5555-5555-5555-555555555961',
    2500,
    '56555555-5555-5555-5555-555555555961'
), (
    '57555555-5555-5555-5555-555555555962',
    0,
    '56555555-5555-5555-5555-555555555962'
);

-- Checked-in attendees with select answers
insert into event_attendee (
    event_id, user_id, checked_in, checked_in_at, created_at, registration_answers
) values (
    '55555555-5555-5555-5555-555555555961',
    '77777777-7777-7777-7777-777777777961',
    true,
    now() - interval '3 days' - interval '10 minutes',
    now() - interval '10 days',
    '{"answers": [{"question_id": "5a555555-5555-5555-5555-555555555961", "value": "5b555555-5555-5555-5555-555555555961"}]}'::jsonb
), (
    '55555555-5555-5555-5555-555555555961',
    '77777777-7777-7777-7777-777777777962',
    true,
    now() - interval '3 days' + interval '5 minutes',
    now() - interval '6 days',
    '{"answers": [{"question_id": "5a555555-5555-5555-5555-555555555961", "value": "5b555555-5555-5555-5555-555555555962"}]}'::jsonb
);

-- Completed purchases holding the attendee seats
insert into event_purchase (
    event_purchase_id, amount_minor, charge_model, completed_at, currency_code,
    discount_amount_minor, event_id, event_ticket_type_id, status, ticket_title, user_id
) values (
    '58555555-5555-5555-5555-555555555961',
    2500,
    'external',
    now() - interval '10 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555961',
    '56555555-5555-5555-5555-555555555961',
    'completed',
    'Analytics pass',
    '77777777-7777-7777-7777-777777777961'
), (
    '58555555-5555-5555-5555-555555555962',
    2500,
    'external',
    now() - interval '6 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555961',
    '56555555-5555-5555-5555-555555555961',
    'completed',
    'Analytics pass',
    '77777777-7777-7777-7777-777777777962'
);

-- Daily page views of the analytics events
insert into event_views (event_id, day, total) values
    ('55555555-5555-5555-5555-555555555961', current_date - 15, 12),
    ('55555555-5555-5555-5555-555555555961', current_date - 10, 20),
    ('55555555-5555-5555-5555-555555555961', current_date - 6, 9),
    ('55555555-5555-5555-5555-555555555962', current_date - 1, 4);

-- Attributed page views of the past analytics event
insert into event_views_utm (event_id, day, total, utm_campaign, utm_medium, utm_source) values
    ('55555555-5555-5555-5555-555555555961', current_date - 10, 6, '', 'email', 'newsletter'),
    ('55555555-5555-5555-5555-555555555961', current_date - 10, 3, '', 'social', 'mastodon'),
    ('55555555-5555-5555-5555-555555555961', current_date - 6, 2, 'spring', '', '');
