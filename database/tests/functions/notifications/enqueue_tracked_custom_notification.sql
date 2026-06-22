-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '8a070000-0000-0000-0000-000000000001'
\set groupCategoryID '8a070000-0000-0000-0000-000000000002'
\set groupID '8a070000-0000-0000-0000-000000000003'
\set senderID '8a070000-0000-0000-0000-000000000004'
\set recipientID '8a070000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'tracked-custom-notification-alliance',
    'Tracked Custom Notification Alliance',
    'Alliance used for tracked custom notification tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Test Group', 'test-group');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'senderID', gen_random_bytes(32), 'sender@example.com', true, 'sender'),
    (:'recipientID', gen_random_bytes(32), 'recipient@example.com', true, 'recipient');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should enqueue and track a custom notification atomically.
select lives_ok(
    format(
        $$select enqueue_tracked_custom_notification(
            'group-custom',
            jsonb_build_object('subject', 'Group update'),
            '[]'::jsonb,
            array[%L::uuid],
            %L::uuid,
            null::uuid,
            %L::uuid,
            1,
            'Group update',
            'Body for group notification'
        )$$,
        :'recipientID',
        :'senderID',
        :'groupID'
    ),
    'Should enqueue and track a custom notification atomically'
);

-- Should create one notification row.
select is(
    (select count(*) from notification where kind = 'group-custom'),
    1::bigint,
    'Should create one notification row'
);

-- Should create one custom notification row.
select is(
    (select count(*) from custom_notification where subject = 'Group update'),
    1::bigint,
    'Should create one custom notification row'
);

-- Should create one audit row.
select is(
    (select count(*) from audit_log where action = 'group_custom_notification_sent'),
    1::bigint,
    'Should create one audit row'
);

-- Should roll back tracking when enqueue fails.
select throws_ok(
    format(
        $$select enqueue_tracked_custom_notification(
            'missing-kind',
            '{}'::jsonb,
            '[]'::jsonb,
            array[%L::uuid],
            %L::uuid,
            null::uuid,
            %L::uuid,
            1,
            'Rolled back',
            'This should not be tracked'
        )$$,
        :'recipientID',
        :'senderID',
        :'groupID'
    ),
    '23503',
    null,
    'Should roll back tracking when enqueue fails'
);

-- Should not track the failed custom notification.
select is(
    (select count(*) from custom_notification where subject = 'Rolled back'),
    0::bigint,
    'Should not track the failed custom notification'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
