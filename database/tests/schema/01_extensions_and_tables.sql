-- Tests database extensions and tables.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should have the pgcrypto extension
select has_extension('pgcrypto');

-- Should have the postgis extension
select has_extension('postgis');

-- Should contain exactly the application, PostGIS and tern tables in public
select tables_are(
    'public',
    array[
        'admission_offer',
        'attachment',
        'audit_log',
        'auth_session',
        'badge',
        'badge_artwork',
        'badge_award_job',
        'badge_award_job_recipient',
        'badge_status_list',
        'cfs_submission',
        'cfs_submission_label',
        'cfs_submission_rating',
        'cfs_submission_status',
        'community',
        'community_permission',
        'community_redirect_settings',
        'community_role',
        'community_role_community_permission',
        'community_role_group_permission',
        'community_site_layout',
        'community_team',
        'community_views',
        'custom_notification',
        'email_verification_code',
        'event',
        'event_attendee',
        'event_category',
        'event_cohost',
        'event_cohost_status',
        'event_discount_code',
        'event_host',
        'event_invitation_request',
        'event_kind',
        'event_label',
        'event_organizer',
        'event_purchase',
        'event_purchase_application_fee_adjustment',
        'event_purchase_credit_note',
        'event_purchase_refund',
        'event_refund_request',
        'event_series',
        'event_speaker',
        'event_sponsor',
        'event_survey',
        'event_survey_response',
        'event_ticket_price_window',
        'event_ticket_type',
        'event_views',
        'event_views_utm',
        'event_waitlist',
        'external_payments_config',
        'group',
        'group_category',
        'group_member',
        'group_permission',
        'group_role',
        'group_role_group_permission',
        'group_site_layout',
        'group_sponsor',
        'group_team',
        'group_views',
        'images',
        'inbox_conversation',
        'inbox_conversation_status',
        'inbox_message',
        'legacy_event_host',
        'legacy_event_speaker',
        'meeting',
        'meeting_auto_end_check_outcome',
        'meeting_provider',
        'notification',
        'notification_attachment',
        'notification_category',
        'notification_kind',
        'notification_template_data',
        'payment_job',
        'payment_provider',
        'payment_provider_tax_location',
        'payment_provider_tax_product',
        'region',
        'session',
        'session_kind',
        'session_label',
        'session_proposal',
        'session_proposal_level',
        'session_proposal_status',
        'session_speaker',
        'site',
        'spatial_ref_sys',
        'user',
        'user_badge',
        'user_group_notification_mute',
        'user_notification_opt_out',
        'utm_medium',
        'version_functions',
        'version_schema'
    ],
    'Should contain exactly the expected tables in public'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
