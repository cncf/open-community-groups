-- E2E seed: speakers, audit logs, sessions, and session speakers.
-- Depends on: 70_payments.sql (events, users, attendees, and purchases).

-- ============================================================================
-- EVENT SPEAKERS
-- ============================================================================

insert into event_speaker (event_id, user_id, featured)
values (
    '55555555-5555-5555-5555-555555555501',
    '77777777-7777-7777-7777-777777777705',
    true
), (
    '55555555-5555-5555-5555-555555555501',
    '77777777-7777-7777-7777-777777777706',
    false
);

-- ============================================================================
-- AUDIT LOGS
-- ============================================================================

insert into audit_log (
    audit_log_id,
    action,
    created_at,
    resource_id,
    resource_type,
    actor_user_id,
    actor_username,
    community_id,
    details,
    event_id,
    group_id
) values (
    '88888888-8888-8888-8888-888888888801',
    'community_updated',
    now() - interval '6 hours',
    '11111111-1111-1111-1111-111111111111',
    'community',
    '77777777-7777-7777-7777-777777777701',
    'e2e-admin-1',
    '11111111-1111-1111-1111-111111111111',
    '{}'::jsonb,
    null,
    null
), (
    '88888888-8888-8888-8888-888888888802',
    'group_added',
    now() - interval '5 hours',
    '44444444-4444-4444-4444-444444444443',
    'group',
    '77777777-7777-7777-7777-777777777701',
    'e2e-admin-1',
    '11111111-1111-1111-1111-111111111111',
    '{"region":"North America","status":"Active"}'::jsonb,
    null,
    null
), (
    '88888888-8888-8888-8888-888888888803',
    'group_updated',
    now() - interval '4 hours',
    '44444444-4444-4444-4444-444444444441',
    'group',
    '77777777-7777-7777-7777-777777777703',
    'e2e-organizer-1',
    '11111111-1111-1111-1111-111111111111',
    '{}'::jsonb,
    null,
    '44444444-4444-4444-4444-444444444441'
), (
    '88888888-8888-8888-8888-888888888804',
    'group_sponsor_added',
    now() - interval '3 hours',
    '66666666-6666-6666-6666-666666666601',
    'group_sponsor',
    '77777777-7777-7777-7777-777777777703',
    'e2e-organizer-1',
    '11111111-1111-1111-1111-111111111111',
    '{"tier":"gold","website":"https://techcorp.example.com"}'::jsonb,
    null,
    '44444444-4444-4444-4444-444444444441'
), (
    '88888888-8888-8888-8888-888888888805',
    'user_details_updated',
    now() - interval '2 hours',
    '77777777-7777-7777-7777-777777777705',
    'user',
    '77777777-7777-7777-7777-777777777705',
    'e2e-member-1',
    null,
    '{}'::jsonb,
    null,
    null
), (
    '88888888-8888-8888-8888-888888888806',
    'session_proposal_added',
    now() - interval '1 hour',
    '99999999-9999-9999-9999-999999999801',
    'session_proposal',
    '77777777-7777-7777-7777-777777777705',
    'e2e-member-1',
    null,
    '{"source":"Seeded logs fixture","level":"advanced"}'::jsonb,
    null,
    null
);

-- ============================================================================
-- SESSIONS
-- ============================================================================

insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    description,
    cfs_submission_id
)
values (
    '88888888-8888-8888-8888-888888888801',
    '55555555-5555-5555-5555-555555555501',
    'Opening Keynote',
    'in-person',
    now() + interval '10 days',
    now() + interval '10 days 1 hour',
    'Welcome and introduction to the event.',
    null
), (
    '88888888-8888-8888-8888-888888888802',
    '55555555-5555-5555-5555-555555555501',
    'Technical Workshop',
    'in-person',
    now() + interval '10 days 1 hour',
    now() + interval '10 days 2 hours',
    'Hands-on technical session.',
    null
), (
    '88888888-8888-8888-8888-888888888803',
    '55555555-5555-5555-5555-555555555519',
    'Scaling Community Workshops Session',
    'virtual',
    date_trunc('day', now()) + interval '45 days 11 hours',
    date_trunc('day', now()) + interval '45 days 11 hours 45 minutes',
    'Approved proposal linked into the CFS agenda.',
    '99999999-9999-9999-9999-999999999913'
), (
    '88888888-8888-8888-8888-888888888804',
    '55555555-5555-5555-5555-555555555535',
    'Summit Kickoff',
    'virtual',
    now() + interval '40 days',
    now() + interval '40 days 1 hour',
    'First day opening for the multi-day summit.',
    null
), (
    '88888888-8888-8888-8888-888888888805',
    '55555555-5555-5555-5555-555555555535',
    'Summit Wrap-Up',
    'virtual',
    now() + interval '41 days',
    now() + interval '41 days 1 hour',
    'Second day closing for the multi-day summit.',
    null
);

-- Live event session used to verify per-session join links for attendees.
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    description,
    meeting_join_url,
    cfs_submission_id
)
values (
    '88888888-8888-8888-8888-888888888806',
    '55555555-5555-5555-5555-555555555529',
    'Live Check-In Briefing',
    'virtual',
    now() + interval '1 hour',
    now() + interval '2 hours',
    'Session used to verify the attendee-only join link.',
    'https://meet.example.com/e2e-live-briefing',
    null
);

-- ============================================================================
-- SESSION SPEAKERS
-- ============================================================================

insert into session_speaker (session_id, user_id, featured)
values (
    '88888888-8888-8888-8888-888888888801',
    '77777777-7777-7777-7777-777777777705',
    true
), (
    '88888888-8888-8888-8888-888888888801',
    '77777777-7777-7777-7777-777777777706',
    false
), (
    '88888888-8888-8888-8888-888888888803',
    '77777777-7777-7777-7777-777777777705',
    true
);
