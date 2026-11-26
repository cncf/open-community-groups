-- Tests deleting unreferenced notification template data rows.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notifID '0a180000-0000-0000-0000-000000000021'
\set tplReferencedID '0a180000-0000-0000-0000-000000000011'
\set tplUnreferencedID '0a180000-0000-0000-0000-000000000012'
\set userID '0a180000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Template data row still referenced by a notification
insert into notification_template_data (notification_template_data_id, data, hash)
values (
    :'tplReferencedID',
    '{"link":"https://example.test/keep"}'::jsonb,
    encode(digest('0a18-referenced', 'sha256'), 'hex')
);

-- Unreferenced template data row eligible for deletion
insert into notification_template_data (notification_template_data_id, data, hash)
values (
    :'tplUnreferencedID',
    '{"link":"https://example.test/delete"}'::jsonb,
    encode(digest('0a18-unreferenced', 'sha256'), 'hex')
);

-- User owning the referencing notification
select fx_user(:'userID');

-- Notification holding a reference to the kept template data row
insert into notification (notification_id, delivery_status, kind, notification_template_data_id, user_id)
values (:'notifID', 'pending', 'password-reset', :'tplReferencedID', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept null and empty template data id arrays
select lives_ok(
    $$select delete_unreferenced_notification_template_data(null)$$,
    'Should accept a null template data id array'
);
select lives_ok(
    $$select delete_unreferenced_notification_template_data('{}'::uuid[])$$,
    'Should accept an empty template data id array'
);

-- Should delete unreferenced rows while keeping still-referenced rows
select lives_ok(
    format(
        $$select delete_unreferenced_notification_template_data(array[%L::uuid, %L::uuid])$$,
        :'tplReferencedID',
        :'tplUnreferencedID'
    ),
    'Should run deletion for mixed referenced and unreferenced ids'
);
select results_eq(
    format(
        $$
            select notification_template_data_id
            from notification_template_data
            where notification_template_data_id in (%L::uuid, %L::uuid)
            order by notification_template_data_id
        $$,
        :'tplReferencedID',
        :'tplUnreferencedID'
    ),
    format($$values (%L::uuid)$$, :'tplReferencedID'),
    'Should keep referenced template data and remove unreferenced template data'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
