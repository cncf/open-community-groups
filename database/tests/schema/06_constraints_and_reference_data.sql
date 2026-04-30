-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(46);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: custom_notification table expected constraints exist
select has_check('custom_notification');

-- Test: community redirect settings table expected constraints exist
select has_check(
    'community_redirect_settings',
    'community_redirect_settings_base_legacy_url_chk'
);

-- Test: community redirect settings should accept absolute legacy origin URLs
select lives_ok(
    $$
        with inserted_community as (
            insert into community (
                community_id,
                name,
                display_name,
                description,
                logo_url,
                banner_mobile_url,
                banner_url
            ) values (
                '00000000-0000-0000-0000-000000000501',
                'redirect-settings-valid',
                'Redirect Settings Valid',
                'A community with valid redirect settings',
                'https://example.com/logo-valid.png',
                'https://example.com/banner-mobile-valid.png',
                'https://example.com/banner-valid.png'
            )
            returning community_id
        )
        insert into community_redirect_settings (
            community_id,

            base_legacy_url
        )
        select
            community_id,

            'https://legacy.example.org'
        from inserted_community
    $$,
    'Community redirect settings should accept absolute legacy origin URLs'
);

-- Test: community redirect settings should reject legacy URLs with paths
select throws_ok(
    $$
        with inserted_community as (
            insert into community (
                community_id,
                name,
                display_name,
                description,
                logo_url,
                banner_mobile_url,
                banner_url
            ) values (
                '00000000-0000-0000-0000-000000000503',
                'redirect-settings-path',
                'Redirect Settings Path',
                'A community with invalid redirect settings',
                'https://example.com/logo-path.png',
                'https://example.com/banner-mobile-path.png',
                'https://example.com/banner-path.png'
            )
            returning community_id
        )
        insert into community_redirect_settings (
            community_id,

            base_legacy_url
        )
        select
            community_id,

            'https://legacy.example.org/path'
        from inserted_community
    $$,
    '23514',
    'new row for relation "community_redirect_settings" violates check constraint "community_redirect_settings_base_legacy_url_chk"',
    'Community redirect settings should reject legacy URLs with paths'
);

-- Test: community redirect settings should reject relative legacy URLs
select throws_ok(
    $$
        with inserted_community as (
            insert into community (
                community_id,
                name,
                display_name,
                description,
                logo_url,
                banner_mobile_url,
                banner_url
            ) values (
                '00000000-0000-0000-0000-000000000502',
                'redirect-settings-invalid',
                'Redirect Settings Invalid',
                'A community with invalid redirect settings',
                'https://example.com/logo-invalid.png',
                'https://example.com/banner-mobile-invalid.png',
                'https://example.com/banner-invalid.png'
            )
            returning community_id
        )
        insert into community_redirect_settings (
            community_id,

            base_legacy_url
        )
        select
            community_id,

            'legacy.example.org'
        from inserted_community
    $$,
    '23514',
    'new row for relation "community_redirect_settings" violates check constraint "community_redirect_settings_base_legacy_url_chk"',
    'Community redirect settings should reject relative legacy URLs'
);

-- Test: event table expected constraints exist
select has_check('event', 'event_check');
select has_check('event', 'event_check2');
select has_check('event', 'event_cfs_fields_chk');
select has_check('event', 'event_cfs_window_chk');
select has_check('event', 'event_attendee_approval_waitlist_exclusive_chk');
select has_check('event', 'event_meeting_capacity_required_chk');
select has_check('event', 'event_meeting_conflict_chk');
select has_check('event', 'event_meeting_kind_chk');
select has_check('event', 'event_meeting_provider_required_chk');
select has_check('event', 'event_meeting_requested_times_chk');
select has_check('event', 'event_waitlist_capacity_required_chk');

-- Test: event invitation request table expected constraints exist
select has_check('event_invitation_request');

-- Test: event discount code table expected constraints exist
select has_check('event_discount_code', 'event_discount_code_kind_value_chk');
select has_check('event_discount_code', 'event_discount_code_window_chk');

-- Test: event ticket price window table expected constraints exist
select has_check('event_ticket_price_window', 'event_ticket_price_window_window_chk');

-- Test: group table expected constraints exist
select has_check('group', 'group_check');

-- Test: session table expected constraints exist
select has_check('session', 'session_check');
select has_check('session', 'session_meeting_conflict_chk');
select has_check('session', 'session_meeting_provider_required_chk');
select has_check('session', 'session_meeting_requested_times_chk');

-- Test: event purchase statuses should match expected values
select results_eq(
    $$
        select (regexp_matches(pg_get_constraintdef(oid), $re$'([^']+)'$re$, 'g'))[1]
        from pg_constraint
        where conname = 'event_purchase_status_check'
    $$,
    $$ values
        ('completed'),
        ('expired'),
        ('pending'),
        ('refund-pending'),
        ('refund-requested'),
        ('refunded')
    $$,
    'Event purchase statuses should match expected values'
);

-- Test: event kinds should match expected values
select results_eq(
    'select * from event_kind order by event_kind_id',
    $$ values
        ('hybrid', 'Hybrid'),
        ('in-person', 'In Person'),
        ('virtual', 'Virtual')
    $$,
    'Event kinds should exist'
);

-- Test: meeting auto end check outcome should match expected values
select results_eq(
    'select * from meeting_auto_end_check_outcome order by meeting_auto_end_check_outcome_id',
    $$ values
        ('already_not_running', 'Already not running'),
        ('auto_ended', 'Auto ended'),
        ('error', 'Error'),
        ('not_found', 'Not found')
    $$,
    'Meeting auto-end check outcomes should exist'
);

-- Test: meeting providers should match expected values
select results_eq(
    'select * from meeting_provider order by meeting_provider_id',
    $$ values
        ('zoom', 'Zoom')
    $$,
    'Meeting providers should exist'
);

-- Test: notification table expected constraints exist
select has_check('notification', 'notification_delivery_attempts_chk');
select has_check('notification', 'notification_delivery_status_chk');

-- Test: payment providers should match expected values
select results_eq(
    'select * from payment_provider order by payment_provider_id',
    $$ values
        ('stripe', 'Stripe')
    $$,
    'Payment providers should exist'
);

-- Test: CFS submission statuses should match expected values
select results_eq(
    'select * from cfs_submission_status order by cfs_submission_status_id',
    $$ values
        ('approved', 'Approved'),
        ('information-requested', 'Information requested'),
        ('not-reviewed', 'Not reviewed'),
        ('rejected', 'Rejected'),
        ('withdrawn', 'Withdrawn')
    $$,
    'CFS submission statuses should exist'
);

-- Test: notification kinds should match expected values
select results_eq(
    'select name from notification_kind order by name',
    $$ values
        ('cfs-submission-updated'),
        ('community-team-invitation'),
        ('email-verification'),
        ('event-canceled'),
        ('event-custom'),
        ('event-published'),
        ('event-refund-approved'),
        ('event-refund-rejected'),
        ('event-refund-requested'),
        ('event-reminder'),
        ('event-rescheduled'),
        ('event-series-canceled'),
        ('event-series-published'),
        ('event-waitlist-joined'),
        ('event-waitlist-left'),
        ('event-waitlist-promoted'),
        ('event-welcome'),
        ('group-custom'),
        ('group-team-invitation'),
        ('group-welcome'),
        ('session-proposal-co-speaker-invitation'),
        ('speaker-series-welcome'),
        ('speaker-welcome')
    $$,
    'Notification kinds should exist'
);

-- Test: session kinds should match expected values
select results_eq(
    'select * from session_kind order by session_kind_id',
    $$ values
        ('hybrid', 'Hybrid'),
        ('in-person', 'In-Person'),
        ('virtual', 'Virtual')
    $$,
    'Session kinds should exist'
);

-- Test: session proposal levels should match expected values
select results_eq(
    'select * from session_proposal_level order by session_proposal_level_id',
    $$ values
        ('advanced', 'Advanced'),
        ('beginner', 'Beginner'),
        ('intermediate', 'Intermediate')
    $$,
    'Session proposal levels should exist'
);

-- Test: session proposal statuses should match expected values
select results_eq(
    'select * from session_proposal_status order by session_proposal_status_id',
    $$ values
        ('declined-by-co-speaker', 'Declined by co-speaker'),
        ('pending-co-speaker-response', 'Awaiting co-speaker response'),
        ('ready-for-submission', 'Ready for submission')
    $$,
    'Session proposal statuses should exist'
);

-- Test: community site layout should match expected
select results_eq(
    'select * from community_site_layout',
    $$ values ('default') $$,
    'Community site layout should have default'
);

-- Test: community role should match expected values
select results_eq(
    'select * from community_role order by community_role_id',
    $$ values
        ('admin', 'Admin'),
        ('groups-manager', 'Groups Manager'),
        ('viewer', 'Viewer')
    $$,
    'Community roles should exist'
);

-- Test: community permissions should match expected values
select results_eq(
    'select community_permission_id, display_name from community_permission order by community_permission_id',
    $$ values
        ('community.groups.write', 'Groups Write'),
        ('community.read', 'Read'),
        ('community.settings.write', 'Settings Write'),
        ('community.taxonomy.write', 'Taxonomy Write'),
        ('community.team.write', 'Team Write')
    $$,
    'Community permissions should exist'
);

-- Test: community role to community permission mapping should match expected values
select results_eq(
    'select community_permission_id, community_role_id from community_role_community_permission order by community_permission_id, community_role_id',
    $$ values
        ('community.groups.write', 'admin'),
        ('community.groups.write', 'groups-manager'),
        ('community.read', 'admin'),
        ('community.read', 'groups-manager'),
        ('community.read', 'viewer'),
        ('community.settings.write', 'admin'),
        ('community.taxonomy.write', 'admin'),
        ('community.team.write', 'admin')
    $$,
    'Community role to community permission mapping should exist'
);

-- Test: community role to group permission mapping should match expected values
select results_eq(
    'select community_role_id, group_permission_id from community_role_group_permission order by community_role_id, group_permission_id',
    $$ values
        ('admin', 'group.events.write'),
        ('admin', 'group.members.write'),
        ('admin', 'group.read'),
        ('admin', 'group.settings.write'),
        ('admin', 'group.sponsors.write'),
        ('admin', 'group.team.write'),
        ('groups-manager', 'group.events.write'),
        ('groups-manager', 'group.members.write'),
        ('groups-manager', 'group.read'),
        ('groups-manager', 'group.settings.write'),
        ('groups-manager', 'group.sponsors.write'),
        ('groups-manager', 'group.team.write'),
        ('viewer', 'group.read')
    $$,
    'Community role to group permission mapping should exist'
);

-- Test: group permissions should match expected values
select results_eq(
    'select group_permission_id, display_name from group_permission order by group_permission_id',
    $$ values
        ('group.events.write', 'Events Write'),
        ('group.members.write', 'Members Write'),
        ('group.read', 'Read'),
        ('group.settings.write', 'Settings Write'),
        ('group.sponsors.write', 'Sponsors Write'),
        ('group.team.write', 'Team Write')
    $$,
    'Group permissions should exist'
);

-- Test: group role should match expected values
select results_eq(
    'select * from group_role order by group_role_id',
    $$ values
        ('admin', 'Admin'),
        ('events-manager', 'Events Manager'),
        ('viewer', 'Viewer')
    $$,
    'Group roles should exist'
);

-- Test: group role to group permission mapping should match expected values
select results_eq(
    'select group_permission_id, group_role_id from group_role_group_permission order by group_permission_id, group_role_id',
    $$ values
        ('group.events.write', 'admin'),
        ('group.events.write', 'events-manager'),
        ('group.members.write', 'admin'),
        ('group.read', 'admin'),
        ('group.read', 'events-manager'),
        ('group.read', 'viewer'),
        ('group.settings.write', 'admin'),
        ('group.sponsors.write', 'admin'),
        ('group.team.write', 'admin')
    $$,
    'Group role to group permission mapping should exist'
);

-- Test: group site layout should match expected
select results_eq(
    'select * from group_site_layout',
    $$ values ('default') $$,
    'Group site layout should have default'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
