-- E2E seed: membership, CFS, sponsors, hosts, and organizers.
-- Depends on: 40_users_badges.sql (users, groups, events, and badge fixtures).

-- ============================================================================
-- COMMUNITY TEAM
-- Accepted roles and pending invitations for community dashboards
-- ============================================================================

-- Accepted admin for the primary community
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111111',
    '77777777-7777-7777-7777-777777777701',
    true,
    'admin'
);

-- Accepted admin for the secondary community
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111112',
    '77777777-7777-7777-7777-777777777702',
    true,
    'admin'
);

-- Accepted admin for the dedicated empty-state community
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111113',
    '77777777-7777-7777-7777-777777777701',
    true,
    'admin'
);

-- Primary admin can switch to the secondary community in read-only mode.
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111112',
    '77777777-7777-7777-7777-777777777701',
    true,
    'viewer'
);

-- Groups manager for the primary community
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111111',
    '77777777-7777-7777-7777-777777777709',
    true,
    'groups-manager'
);

-- Read-only viewer for the primary community dashboard
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111111',
    '77777777-7777-7777-7777-777777777710',
    true,
    'viewer'
);

-- Pending invitation for the primary community team
insert into community_team (community_id, user_id, accepted, role)
values (
    '11111111-1111-1111-1111-111111111111',
    '77777777-7777-7777-7777-777777777707',
    false,
    'viewer'
);

-- ============================================================================
-- GROUP TEAM
-- Accepted roles and pending invitations for group dashboards
-- ============================================================================

-- Accepted organizer for the primary group
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777703',
    true,
    'admin'
);

-- Accepted organizer for the dedicated empty-state group
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444447',
    '77777777-7777-7777-7777-777777777703',
    true,
    'admin'
);

insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444448',
    '77777777-7777-7777-7777-777777777703',
    true,
    'admin'
);

-- Accepted organizer for the Delta group
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444444',
    '77777777-7777-7777-7777-777777777704',
    true,
    'admin'
);

-- Primary organizer can switch to another group in read-only mode.
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444443',
    '77777777-7777-7777-7777-777777777703',
    true,
    'viewer'
);

-- Events manager for the primary group
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777711',
    true,
    'events-manager'
);

-- Read-only viewer for the primary group dashboard
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777712',
    true,
    'viewer'
);

-- Check-in manager for the primary group dashboard.
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777715',
    true,
    'check-in-manager'
);

-- Pending invitation for the secondary group team
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444442',
    '77777777-7777-7777-7777-777777777707',
    false,
    'events-manager'
);

-- Pending viewer invitation for the primary group team
insert into group_team (group_id, user_id, accepted, role)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777708',
    false,
    'viewer'
);

-- ============================================================================
-- GROUP MEMBERS
-- Membership relationships used by site and dashboard flows
-- ============================================================================

-- Member of the primary and secondary groups
insert into group_member (group_id, user_id)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777705'
), (
    '44444444-4444-4444-4444-444444444442',
    '77777777-7777-7777-7777-777777777705'
);

-- Second primary group member so the members tab can paginate. Backdated so
-- the group analytics members running total spans more than one month.
insert into group_member (group_id, user_id, created_at)
values (
    '44444444-4444-4444-4444-444444444441',
    '77777777-7777-7777-7777-777777777714',
    now() - interval '3 months'
);

-- Member of the Delta and Epsilon groups
insert into group_member (group_id, user_id)
values (
    '44444444-4444-4444-4444-444444444444',
    '77777777-7777-7777-7777-777777777706'
), (
    '44444444-4444-4444-4444-444444444445',
    '77777777-7777-7777-7777-777777777706'
);

-- ============================================================================
-- EVENT CFS LABELS
-- ============================================================================

insert into event_cfs_label (event_cfs_label_id, event_id, name, color)
values (
    '99999999-9999-9999-9999-999999999701',
    '55555555-5555-5555-5555-555555555519',
    'Platform',
    '#0284C7'
), (
    '99999999-9999-9999-9999-999999999702',
    '55555555-5555-5555-5555-555555555519',
    'Workshop',
    '#16A34A'
);

-- ============================================================================
-- SESSION PROPOSALS
-- ============================================================================

insert into session_proposal (
    session_proposal_id,
    user_id,
    title,
    description,
    session_proposal_level_id,
    duration,
    co_speaker_user_id,
    session_proposal_status_id,
    updated_at
) values (
    '99999999-9999-9999-9999-999999999801',
    '77777777-7777-7777-7777-777777777705',
    'Cloud Native Operations Deep Dive',
    'A ready proposal that has not been submitted yet.',
    'advanced',
    interval '45 minutes',
    null,
    'ready-for-submission',
    now() - interval '3 days'
), (
    '99999999-9999-9999-9999-999999999802',
    '77777777-7777-7777-7777-777777777705',
    'Platform Reliability Patterns',
    'A proposal already submitted to the open CFS event.',
    'intermediate',
    interval '30 minutes',
    null,
    'ready-for-submission',
    now() - interval '4 days'
), (
    '99999999-9999-9999-9999-999999999803',
    '77777777-7777-7777-7777-777777777705',
    'Observability in Practice',
    'A proposal that needs additional details before approval.',
    'beginner',
    interval '30 minutes',
    null,
    'ready-for-submission',
    now() - interval '2 days'
), (
    '99999999-9999-9999-9999-999999999804',
    '77777777-7777-7777-7777-777777777705',
    'Scaling Community Workshops',
    'An approved proposal linked to a scheduled session.',
    'intermediate',
    interval '45 minutes',
    null,
    'ready-for-submission',
    now() - interval '1 day'
), (
    '99999999-9999-9999-9999-999999999805',
    '77777777-7777-7777-7777-777777777705',
    'Maintainer Burnout Lessons',
    'A proposal that was reviewed and rejected.',
    'advanced',
    interval '30 minutes',
    null,
    'ready-for-submission',
    now() - interval '5 days'
), (
    '99999999-9999-9999-9999-999999999806',
    '77777777-7777-7777-7777-777777777705',
    'Speaker Office Hours',
    'A proposal that was submitted and then withdrawn.',
    'beginner',
    interval '30 minutes',
    null,
    'ready-for-submission',
    now() - interval '6 days'
), (
    '99999999-9999-9999-9999-999999999807',
    '77777777-7777-7777-7777-777777777705',
    'Collaborative Roadmaps',
    'A proposal waiting for the co-speaker response.',
    'intermediate',
    interval '45 minutes',
    '77777777-7777-7777-7777-777777777706',
    'pending-co-speaker-response',
    now() - interval '1 day'
), (
    '99999999-9999-9999-9999-999999999808',
    '77777777-7777-7777-7777-777777777705',
    'Co-Speaker Retrospective',
    'A proposal whose co-speaker declined the invitation.',
    'beginner',
    interval '30 minutes',
    '77777777-7777-7777-7777-777777777706',
    'declined-by-co-speaker',
    now() - interval '7 days'
);

-- ============================================================================
-- CFS SUBMISSIONS
-- ============================================================================

insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id,
    action_required_message,
    reviewed_by,
    updated_at
) values (
    '99999999-9999-9999-9999-999999999911',
    '55555555-5555-5555-5555-555555555519',
    '99999999-9999-9999-9999-999999999802',
    'not-reviewed',
    null,
    null,
    now() - interval '4 days'
), (
    '99999999-9999-9999-9999-999999999912',
    '55555555-5555-5555-5555-555555555519',
    '99999999-9999-9999-9999-999999999803',
    'information-requested',
    'Please add clearer audience outcomes before we continue the review.',
    '77777777-7777-7777-7777-777777777703',
    now() - interval '2 days'
), (
    '99999999-9999-9999-9999-999999999913',
    '55555555-5555-5555-5555-555555555519',
    '99999999-9999-9999-9999-999999999804',
    'approved',
    null,
    '77777777-7777-7777-7777-777777777703',
    now() - interval '1 day'
), (
    '99999999-9999-9999-9999-999999999914',
    '55555555-5555-5555-5555-555555555519',
    '99999999-9999-9999-9999-999999999805',
    'rejected',
    null,
    '77777777-7777-7777-7777-777777777703',
    now() - interval '3 days'
), (
    '99999999-9999-9999-9999-999999999915',
    '55555555-5555-5555-5555-555555555519',
    '99999999-9999-9999-9999-999999999806',
    'withdrawn',
    null,
    null,
    now() - interval '5 hours'
);

insert into cfs_submission_label (cfs_submission_id, event_cfs_label_id)
values (
    '99999999-9999-9999-9999-999999999911',
    '99999999-9999-9999-9999-999999999701'
), (
    '99999999-9999-9999-9999-999999999912',
    '99999999-9999-9999-9999-999999999702'
), (
    '99999999-9999-9999-9999-999999999913',
    '99999999-9999-9999-9999-999999999701'
), (
    '99999999-9999-9999-9999-999999999913',
    '99999999-9999-9999-9999-999999999702'
);

insert into cfs_submission_rating (cfs_submission_id, reviewer_id, stars, comments)
values (
    '99999999-9999-9999-9999-999999999912',
    '77777777-7777-7777-7777-777777777703',
    3,
    'Needs a tighter outline and clearer takeaways.'
), (
    '99999999-9999-9999-9999-999999999913',
    '77777777-7777-7777-7777-777777777703',
    5,
    'Strong structure and audience fit.'
), (
    '99999999-9999-9999-9999-999999999913',
    '77777777-7777-7777-7777-777777777711',
    4,
    'Solid proposal with only minor refinements needed.'
);

-- ============================================================================
-- GROUP SPONSORS
-- ============================================================================

insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url, featured)
values
    (
        '66666666-6666-6666-6666-666666666601',
        '44444444-4444-4444-4444-444444444441',
        'Tech Corp',
        '/static/images/e2e/sponsor-logo.svg',
        'https://techcorp.example.com',
        true
    ),
    (
        '66666666-6666-6666-6666-666666666602',
        '44444444-4444-4444-4444-444444444441',
        'Hidden Sponsor',
        '/static/images/e2e/sponsor-logo.svg',
        'https://hidden-sponsor.example.com',
        false
    );

-- ============================================================================
-- EVENT SPONSORS
-- ============================================================================

insert into event_sponsor (group_sponsor_id, event_id, level)
values (
    '66666666-6666-6666-6666-666666666601',
    '55555555-5555-5555-5555-555555555501',
    'gold'
);

-- ============================================================================
-- EVENT HOSTS
-- ============================================================================

insert into event_host (event_id, user_id)
values (
    '55555555-5555-5555-5555-555555555501',
    '77777777-7777-7777-7777-777777777703'
);

-- ============================================================================
-- EVENT ORGANIZERS
-- ============================================================================

insert into event_organizer (event_id, user_id, "order")
select e.event_id, gt.user_id, gt."order"
from event e
join group_team gt on gt.group_id = e.group_id
where e.legacy_id is null
and gt.accepted = true;
