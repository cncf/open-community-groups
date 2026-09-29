-- E2E seed: group inbox.
-- Depends on: 30_events.sql (primary group event) and 40_users_badges.sql (member and organizer).

-- ============================================================================
-- INBOX CONVERSATIONS
-- ============================================================================

-- Answered conversation between the second member and the primary group
insert into inbox_conversation (
    inbox_conversation_id,
    created_at,
    group_id,
    inbox_conversation_status_id,
    last_message_at,

    event_id,
    user_id
) values (
    'fbfbfbfb-fbfb-fbfb-fbfb-fbfbfbfbfb01',
    date_trunc('day', current_timestamp) - interval '2 days' + interval '10 hours',
    '44444444-4444-4444-4444-444444444441',
    'answered',
    date_trunc('day', current_timestamp) - interval '2 days' + interval '11 hours',

    '55555555-5555-5555-5555-555555555501',
    '77777777-7777-7777-7777-777777777706'
);

-- Messages of the answered conversation
insert into inbox_message (
    inbox_message_id,
    body,
    created_at,
    inbox_conversation_id,
    kind,

    author_user_id
) values (
    'fbfbfbfb-fbfb-fbfb-fbfb-fbfbfbfbfb11',
    'Is the venue step-free?',
    date_trunc('day', current_timestamp) - interval '2 days' + interval '10 hours',
    'fbfbfbfb-fbfb-fbfb-fbfb-fbfbfbfbfb01',
    'initial',

    '77777777-7777-7777-7777-777777777706'
), (
    'fbfbfbfb-fbfb-fbfb-fbfb-fbfbfbfbfb12',
    'Yes, there is a lift at the main entrance.',
    date_trunc('day', current_timestamp) - interval '2 days' + interval '11 hours',
    'fbfbfbfb-fbfb-fbfb-fbfb-fbfbfbfbfb01',
    'group-reply',

    '77777777-7777-7777-7777-777777777703'
);
