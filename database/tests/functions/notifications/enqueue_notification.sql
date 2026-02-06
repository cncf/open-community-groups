-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userID1 '00000000-0000-0000-0000-000000000801'
\set userID2 '00000000-0000-0000-0000-000000000802'
\set userID3 '00000000-0000-0000-0000-000000000803'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (auth_hash, email, email_verified, user_id, username) values
    ('hash-1', 'user1@example.com', true, :'userID1', 'user-one'),
    ('hash-2', 'user2@example.com', true, :'userID2', 'user-two'),
    ('hash-3', 'user3@example.com', false, :'userID3', 'user-three');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should enqueue one notification per recipient without template or attachments
select lives_ok(
    format(
        $$select enqueue_notification(
            'event-published',
            null,
            '[]'::jsonb,
            array[%L, %L]::uuid[]
        )$$,
        :'userID1',
        :'userID2'
    ),
    'Should enqueue one notification per recipient without template or attachments'
);

-- Should create event-published notifications for expected recipients
select results_eq(
    $$
    select
        n.user_id,
        n.notification_template_data_id
    from notification n
    where n.kind = 'event-published'
    order by n.user_id
    $$,
    $$ values
        ('00000000-0000-0000-0000-000000000801'::uuid, null::uuid),
        ('00000000-0000-0000-0000-000000000802'::uuid, null::uuid)
    $$,
    'Should create event-published notifications for expected recipients'
);

-- Should enqueue notifications with deduplicated template data
select lives_ok(
    format(
        $$select enqueue_notification(
            'group-welcome',
            '{"group":"rust"}'::jsonb,
            '[]'::jsonb,
            array[%L, %L]::uuid[]
        )$$,
        :'userID1',
        :'userID3'
    ),
    'Should enqueue notifications with deduplicated template data'
);

-- Should insert template data with expected hash
select results_eq(
    $$
    select
        data,
        hash
    from notification_template_data
    where data = '{"group":"rust"}'::jsonb
    $$,
    $$ values (
        '{"group":"rust"}'::jsonb,
        encode(digest(convert_to('{"group":"rust"}'::jsonb::text, 'utf8'), 'sha256'), 'hex')
    ) $$,
    'Should insert template data with expected hash'
);

-- Should link group-welcome notifications to expected template data
select results_eq(
    $$
    select
        n.user_id,
        td.data
    from notification n
    join notification_template_data td using (notification_template_data_id)
    where n.kind = 'group-welcome'
    order by n.user_id
    $$,
    $$ values
        ('00000000-0000-0000-0000-000000000801'::uuid, '{"group":"rust"}'::jsonb),
        ('00000000-0000-0000-0000-000000000803'::uuid, '{"group":"rust"}'::jsonb)
    $$,
    'Should link group-welcome notifications to expected template data'
);

-- Should reuse template data row for repeated hash
select lives_ok(
    format(
        $$select enqueue_notification(
            'group-welcome',
            '{"group":"rust"}'::jsonb,
            '[]'::jsonb,
            array[%L]::uuid[]
        )$$,
        :'userID2'
    ),
    'Should reuse template data row for repeated hash'
);

-- Should keep one template hash across group-welcome notifications
select results_eq(
    $$
    select
        n.user_id,
        td.hash
    from notification n
    join notification_template_data td using (notification_template_data_id)
    where n.kind = 'group-welcome'
    order by n.user_id
    $$,
    $$ values
        (
            '00000000-0000-0000-0000-000000000801'::uuid,
            encode(digest(convert_to('{"group":"rust"}'::jsonb::text, 'utf8'), 'sha256'), 'hex')
        ),
        (
            '00000000-0000-0000-0000-000000000802'::uuid,
            encode(digest(convert_to('{"group":"rust"}'::jsonb::text, 'utf8'), 'sha256'), 'hex')
        ),
        (
            '00000000-0000-0000-0000-000000000803'::uuid,
            encode(digest(convert_to('{"group":"rust"}'::jsonb::text, 'utf8'), 'sha256'), 'hex')
        )
    $$,
    'Should keep one template hash across group-welcome notifications'
);

-- Should enqueue notifications with deduplicated attachments
select lives_ok(
    format(
        $$select enqueue_notification(
            'event-welcome',
            null,
            jsonb_build_array(
                jsonb_build_object(
                    'content_type', 'text/plain',
                    'data_base64', 'aGVsbG8=',
                    'file_name', 'hello.txt'
                ),
                jsonb_build_object(
                    'content_type', 'application/pdf',
                    'data_base64', 'cGRmLWNvbnRlbnQ=',
                    'file_name', 'ticket.pdf'
                )
            ),
            array[%L, %L]::uuid[]
        )$$,
        :'userID1',
        :'userID2'
    ),
    'Should enqueue notifications with deduplicated attachments'
);

-- Should insert expected attachment rows
select results_eq(
    $$
    select
        content_type,
        file_name,
        data,
        hash
    from attachment
    order by file_name
    $$,
    $$ values
        (
            'text/plain',
            'hello.txt',
            decode('aGVsbG8=', 'base64'),
            '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824'
        ),
        (
            'application/pdf',
            'ticket.pdf',
            decode('cGRmLWNvbnRlbnQ=', 'base64'),
            '3c41d3835155c97d51a836c887be9c0063b7b45f61e14017a9d653fa4c655802'
        )
    $$,
    'Should insert expected attachment rows'
);

-- Should link each event-welcome notification to both attachments
select results_eq(
    $$
    select
        n.user_id,
        array_agg(a.hash order by a.hash) as attachment_hashes
    from notification n
    join notification_attachment na on na.notification_id = n.notification_id
    join attachment a on a.attachment_id = na.attachment_id
    where n.kind = 'event-welcome'
    group by n.user_id
    order by n.user_id
    $$,
    $$ values
        (
            '00000000-0000-0000-0000-000000000801'::uuid,
            array[
                '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
                '3c41d3835155c97d51a836c887be9c0063b7b45f61e14017a9d653fa4c655802'
            ]::text[]
        ),
        (
            '00000000-0000-0000-0000-000000000802'::uuid,
            array[
                '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
                '3c41d3835155c97d51a836c887be9c0063b7b45f61e14017a9d653fa4c655802'
            ]::text[]
        )
    $$,
    'Should link each event-welcome notification to both attachments'
);

-- Should keep template reference null for event-welcome notifications
select results_eq(
    $$
    select
        n.user_id,
        n.notification_template_data_id
    from notification n
    where n.kind = 'event-welcome'
    order by n.user_id
    $$,
    $$ values
        ('00000000-0000-0000-0000-000000000801'::uuid, null::uuid),
        ('00000000-0000-0000-0000-000000000802'::uuid, null::uuid)
    $$,
    'Should keep template reference null for event-welcome notifications'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
