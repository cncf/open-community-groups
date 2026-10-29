-- Tests database constraints and reference data.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(61);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: check constraints should match the expected snapshot
select set_eq(
    $$
        select
            c.conrelid::regclass::text as table_name,
            c.conname::text as constraint_name
        from pg_constraint c
        where c.connamespace = 'public'::regnamespace
        and c.contype = 'c'
        and c.conrelid <> 0
        and not exists (
            select 1
            from pg_depend d
            where d.classid = 'pg_class'::regclass
            and d.objid = c.conrelid
            and d.deptype = 'e'
        )
    $$,
    $$ values
        ('admission_offer', 'admission_offer_amount_minor_check'),
        ('admission_offer', 'admission_offer_currency_code_check'),
        ('admission_offer', 'admission_offer_deadline_chk'),
        ('admission_offer', 'admission_offer_discount_amount_minor_check'),
        ('admission_offer', 'admission_offer_discount_code_check'),
        ('admission_offer', 'admission_offer_snapshot_chk'),
        ('admission_offer', 'admission_offer_source_chk'),
        ('admission_offer', 'admission_offer_status_chk'),
        ('admission_offer', 'admission_offer_ticket_status_snapshot_chk'),
        ('admission_offer', 'admission_offer_ticket_title_check'),
        ('attachment', 'attachment_content_type_check'),
        ('attachment', 'attachment_file_name_check'),
        ('attachment', 'attachment_hash_check'),
        ('audit_log', 'audit_log_action_check'),
        ('audit_log', 'audit_log_actor_username_check'),
        ('audit_log', 'audit_log_details_check'),
        ('audit_log', 'audit_log_resource_type_check'),
        ('badge', 'badge_criteria_chk'),
        ('badge', 'badge_description_chk'),
        ('badge', 'badge_image_file_name_chk'),
        ('badge', 'badge_name_chk'),
        ('badge_artwork', 'badge_artwork_file_name_chk'),
        ('badge_award_job', 'badge_award_job_accepted_count_check'),
        ('badge_award_job', 'badge_award_job_awarded_count_check'),
        ('badge_award_job', 'badge_award_job_badge_snapshot_check'),
        ('badge_award_job', 'badge_award_job_claim_chk'),
        ('badge_award_job', 'badge_award_job_counts_chk'),
        ('badge_award_job', 'badge_award_job_failure_count_check'),
        ('badge_award_job', 'badge_award_job_next_recipient_offset_check'),
        ('badge_award_job', 'badge_award_job_recipient_count_check'),
        ('badge_award_job', 'badge_award_job_skipped_count_check'),
        ('badge_award_job', 'badge_award_job_status_chk'),
        ('badge_award_job', 'badge_award_job_terminal_chk'),
        ('badge_award_job_recipient', 'badge_award_job_recipient_position_check'),
        ('badge_status_list', 'badge_status_list_allocation_offset_chk'),
        ('badge_status_list', 'badge_status_list_allocation_position_chk'),
        ('badge_status_list', 'badge_status_list_allocation_stride_chk'),
        ('cfs_submission', 'cfs_submission_action_required_message_check'),
        ('cfs_submission_rating', 'cfs_submission_rating_comments_check'),
        ('cfs_submission_rating', 'cfs_submission_rating_stars_check'),
        ('cfs_submission_status', 'cfs_submission_status_display_name_check'),
        ('community', 'community_ad_banner_link_url_check'),
        ('community', 'community_ad_banner_url_check'),
        ('community', 'community_banner_mobile_url_check'),
        ('community', 'community_banner_url_check'),
        ('community', 'community_bluesky_url_check'),
        ('community', 'community_description_check'),
        ('community', 'community_display_name_check'),
        ('community', 'community_facebook_url_check'),
        ('community', 'community_flickr_url_check'),
        ('community', 'community_github_url_check'),
        ('community', 'community_instagram_url_check'),
        ('community', 'community_linkedin_url_check'),
        ('community', 'community_logo_url_check'),
        ('community', 'community_name_check'),
        ('community', 'community_new_group_details_check'),
        ('community', 'community_og_image_url_check'),
        ('community', 'community_slack_url_check'),
        ('community', 'community_twitter_url_check'),
        ('community', 'community_website_url_check'),
        ('community', 'community_wechat_url_check'),
        ('community', 'community_youtube_url_check'),
        ('community_permission', 'community_permission_display_name_check'),
        ('community_redirect_settings', 'community_redirect_settings_base_legacy_url_chk'),
        ('community_role', 'community_role_display_name_check'),
        ('custom_notification', 'custom_notification_body_check'),
        ('custom_notification', 'custom_notification_scope_check'),
        ('custom_notification', 'custom_notification_subject_check'),
        ('event', 'event_attendee_approval_waitlist_exclusive_chk'),
        ('event', 'event_banner_mobile_url_check'),
        ('event', 'event_banner_url_check'),
        ('event', 'event_capacity_check'),
        ('event', 'event_cfs_description_check'),
        ('event', 'event_cfs_fields_chk'),
        ('event', 'event_cfs_window_chk'),
        ('event', 'event_check'),
        ('event', 'event_check2'),
        ('event', 'event_description_check'),
        ('event', 'event_description_short_check'),
        ('event', 'event_external_payment_instructions_check'),
        ('event', 'event_external_payment_url_check'),
        ('event', 'event_external_payment_window_hours_check'),
        ('event', 'event_legacy_url_check'),
        ('event', 'event_logo_url_check'),
        ('event', 'event_luma_url_check'),
        ('event', 'event_manual_tax_rate_ids_chk'),
        ('event', 'event_meeting_capacity_required_chk'),
        ('event', 'event_meeting_conflict_chk'),
        ('event', 'event_meeting_error_check'),
        ('event', 'event_meeting_join_instructions_check'),
        ('event', 'event_meeting_join_url_check'),
        ('event', 'event_meeting_kind_chk'),
        ('event', 'event_meeting_provider_host_user_check'),
        ('event', 'event_meeting_provider_required_chk'),
        ('event', 'event_meeting_recording_url_check'),
        ('event', 'event_meeting_requested_times_chk'),
        ('event', 'event_meetup_url_check'),
        ('event', 'event_name_check'),
        ('event', 'event_payment_currency_code_check'),
        ('event', 'event_registration_end_before_event_start_chk'),
        ('event', 'event_registration_start_before_event_start_chk'),
        ('event', 'event_registration_window_order_chk'),
        ('event', 'event_slug_check'),
        ('event', 'event_tax_behavior_chk'),
        ('event', 'event_tax_calculation_mode_chk'),
        ('event', 'event_timezone_check'),
        ('event', 'event_venue_address_check'),
        ('event', 'event_venue_city_check'),
        ('event', 'event_venue_country_code_check'),
        ('event', 'event_venue_country_name_check'),
        ('event', 'event_venue_name_check'),
        ('event', 'event_venue_state_check'),
        ('event', 'event_venue_state_code_check'),
        ('event', 'event_venue_zip_code_check'),
        ('event_attendee', 'event_attendee_attendance_canceled_chk'),
        ('event_attendee', 'event_attendee_status_chk'),
        ('event_category', 'event_category_name_check'),
        ('event_category', 'event_category_slug_check'),
        ('event_cohost', 'event_cohost_approved_at_chk'),
        ('event_cohost', 'event_cohost_pending_approval_chk'),
        ('event_cohost_status', 'event_cohost_status_display_name_check'),
        ('event_discount_code', 'event_discount_code_amount_minor_check'),
        ('event_discount_code', 'event_discount_code_available_check'),
        ('event_discount_code', 'event_discount_code_code_check'),
        ('event_discount_code', 'event_discount_code_kind_check'),
        ('event_discount_code', 'event_discount_code_kind_value_chk'),
        ('event_discount_code', 'event_discount_code_percentage_check'),
        ('event_discount_code', 'event_discount_code_title_check'),
        ('event_discount_code', 'event_discount_code_total_available_check'),
        ('event_discount_code', 'event_discount_code_window_chk'),
        ('event_invitation_request', 'event_invitation_request_check'),
        ('event_invitation_request', 'event_invitation_request_status_check'),
        ('event_label', 'event_label_name_check'),
        ('event_purchase', 'event_purchase_amount_minor_check'),
        ('event_purchase', 'event_purchase_charge_model_chk'),
        ('event_purchase', 'event_purchase_completed_direct_charge_amounts_chk'),
        ('event_purchase', 'event_purchase_connected_seller_id_check'),
        ('event_purchase', 'event_purchase_currency_code_chk'),
        ('event_purchase', 'event_purchase_direct_charge_context_chk'),
        ('event_purchase', 'event_purchase_discount_amount_minor_check'),
        ('event_purchase', 'event_purchase_discount_code_check'),
        ('event_purchase', 'event_purchase_external_chk'),
        ('event_purchase', 'event_purchase_external_payment_details_check'),
        ('event_purchase', 'event_purchase_financial_amounts_chk'),
        ('event_purchase', 'event_purchase_manual_tax_rate_ids_chk'),
        ('event_purchase', 'event_purchase_no_tax_amount_chk'),
        ('event_purchase', 'event_purchase_performance_location_fingerprint_check'),
        ('event_purchase', 'event_purchase_platform_fee_bps_check'),
        ('event_purchase', 'event_purchase_provider_application_fee_id_check'),
        ('event_purchase', 'event_purchase_provider_charge_id_check'),
        ('event_purchase', 'event_purchase_provider_checkout_session_id_check'),
        ('event_purchase', 'event_purchase_provider_checkout_url_check'),
        ('event_purchase', 'event_purchase_provider_invoice_hosted_url_check'),
        ('event_purchase', 'event_purchase_provider_invoice_id_check'),
        ('event_purchase', 'event_purchase_provider_invoice_pdf_url_check'),
        ('event_purchase', 'event_purchase_provider_object_account_id_check'),
        ('event_purchase', 'event_purchase_provider_payment_reference_check'),
        ('event_purchase', 'event_purchase_provider_product_fingerprint_check'),
        ('event_purchase', 'event_purchase_provider_product_mode_chk'),
        ('event_purchase', 'event_purchase_provider_tax_code_check'),
        ('event_purchase', 'event_purchase_provider_tax_location_id_check'),
        ('event_purchase', 'event_purchase_provider_tax_product_id_check'),
        ('event_purchase', 'event_purchase_provisional_platform_fee_amount_minor_chk'),
        ('event_purchase', 'event_purchase_status_check'),
        ('event_purchase', 'event_purchase_tax_behavior_chk'),
        ('event_purchase', 'event_purchase_tax_calculation_mode_chk'),
        ('event_purchase', 'event_purchase_ticket_title_check'),
        (
            'event_purchase_application_fee_adjustment',
            'event_purchase_application_f_provider_application_fee_ref_check'
        ),
        (
            'event_purchase_application_fee_adjustment',
            'event_purchase_application_fee_adjustment_amount_minor_check'
        ),
        (
            'event_purchase_application_fee_adjustment',
            'event_purchase_application_fee_adjustment_kind_chk'
        ),
        ('event_purchase_credit_note', 'event_purchase_credit_note_amount_minor_check'),
        ('event_purchase_credit_note', 'event_purchase_credit_note_currency_code_check'),
        ('event_purchase_credit_note', 'event_purchase_credit_note_provider_credit_note_id_check'),
        ('event_purchase_credit_note', 'event_purchase_credit_note_provider_hosted_url_check'),
        (
            'event_purchase_credit_note',
            'event_purchase_credit_note_provider_object_account_id_check'
        ),
        ('event_purchase_credit_note', 'event_purchase_credit_note_provider_pdf_url_check'),
        ('event_purchase_credit_note', 'event_purchase_credit_note_tax_amount_minor_check'),
        ('event_purchase_refund', 'event_purchase_refund_amount_minor_check'),
        ('event_purchase_refund', 'event_purchase_refund_currency_code_check'),
        ('event_purchase_refund', 'event_purchase_refund_finalized_at_status_chk'),
        ('event_purchase_refund', 'event_purchase_refund_kind_check'),
        ('event_purchase_refund', 'event_purchase_refund_kind_request_chk'),
        ('event_purchase_refund', 'event_purchase_refund_provider_refund_id_check'),
        ('event_purchase_refund', 'event_purchase_refund_provider_refund_required_chk'),
        ('event_purchase_refund', 'event_purchase_refund_status_check'),
        ('event_purchase_refund', 'event_purchase_refund_terminal_failure_chk'),
        ('event_refund_request', 'event_refund_request_requested_reason_check'),
        ('event_refund_request', 'event_refund_request_review_note_check'),
        ('event_refund_request', 'event_refund_request_status_check'),
        ('event_series', 'event_series_recurrence_additional_occurrences_check'),
        ('event_series', 'event_series_recurrence_pattern_check'),
        ('event_series', 'event_series_timezone_check'),
        ('event_sponsor', 'event_sponsor_level_check'),
        ('event_survey', 'event_survey_audience_chk'),
        ('event_survey', 'event_survey_dates_chk'),
        ('event_survey', 'event_survey_description_chk'),
        ('event_survey', 'event_survey_draft_chk'),
        ('event_survey', 'event_survey_open_notification_chk'),
        ('event_survey', 'event_survey_questions_chk'),
        ('event_survey', 'event_survey_revision_chk'),
        ('event_survey', 'event_survey_status_chk'),
        ('event_survey', 'event_survey_title_chk'),
        ('event_survey_response', 'event_survey_response_answers_chk'),
        ('event_ticket_price_window', 'event_ticket_price_window_amount_minor_check'),
        ('event_ticket_price_window', 'event_ticket_price_window_window_chk'),
        ('event_ticket_type', 'event_ticket_type_availability_chk'),
        ('event_ticket_type', 'event_ticket_type_description_check'),
        ('event_ticket_type', 'event_ticket_type_seats_total_check'),
        ('event_ticket_type', 'event_ticket_type_title_check'),
        ('event_views_utm', 'event_views_utm_attribution_chk'),
        ('event_views_utm', 'event_views_utm_utm_campaign_chk'),
        ('event_views_utm', 'event_views_utm_utm_medium_chk'),
        ('event_views_utm', 'event_views_utm_utm_source_chk'),
        ('external_payments_config', 'external_payments_config_allowed_countries_chk'),
        ('external_payments_config', 'external_payments_config_singleton_check'),
        ('external_payments_config', 'external_payments_config_window_hours_chk'),
        ('"group"', 'group_banner_mobile_url_check'),
        ('"group"', 'group_banner_url_check'),
        ('"group"', 'group_bluesky_url_check'),
        ('"group"', 'group_check'),
        ('"group"', 'group_city_check'),
        ('"group"', 'group_country_code_check'),
        ('"group"', 'group_country_name_check'),
        ('"group"', 'group_description_check'),
        ('"group"', 'group_description_short_check'),
        ('"group"', 'group_external_payments_seller_display_name_check'),
        ('"group"', 'group_facebook_url_check'),
        ('"group"', 'group_flickr_url_check'),
        ('"group"', 'group_github_url_check'),
        ('"group"', 'group_instagram_url_check'),
        ('"group"', 'group_legacy_url_check'),
        ('"group"', 'group_linkedin_url_check'),
        ('"group"', 'group_logo_url_check'),
        ('"group"', 'group_name_check'),
        ('"group"', 'group_og_image_url_check'),
        ('"group"', 'group_slack_url_check'),
        ('"group"', 'group_slug_check'),
        ('"group"', 'group_slug_pretty_chk'),
        ('"group"', 'group_state_check'),
        ('"group"', 'group_twitter_url_check'),
        ('"group"', 'group_utm_campaigns_chk'),
        ('"group"', 'group_utm_mediums_chk'),
        ('"group"', 'group_utm_sources_chk'),
        ('"group"', 'group_website_url_check'),
        ('"group"', 'group_wechat_url_check'),
        ('"group"', 'group_youtube_url_check'),
        ('group_category', 'group_category_name_check'),
        ('group_category', 'group_category_normalized_name_check'),
        ('group_permission', 'group_permission_display_name_check'),
        ('group_role', 'group_role_display_name_check'),
        ('group_sponsor', 'group_sponsor_logo_url_check'),
        ('group_sponsor', 'group_sponsor_name_check'),
        ('group_sponsor', 'group_sponsor_website_url_check'),
        ('inbox_conversation_status', 'inbox_conversation_status_display_name_check'),
        ('inbox_message', 'inbox_message_body_chk'),
        ('inbox_message', 'inbox_message_kind_chk'),
        ('legacy_event_host', 'legacy_event_host_bio_check'),
        ('legacy_event_host', 'legacy_event_host_name_check'),
        ('legacy_event_host', 'legacy_event_host_photo_url_check'),
        ('legacy_event_host', 'legacy_event_host_title_check'),
        ('legacy_event_speaker', 'legacy_event_speaker_bio_check'),
        ('legacy_event_speaker', 'legacy_event_speaker_name_check'),
        ('legacy_event_speaker', 'legacy_event_speaker_photo_url_check'),
        ('legacy_event_speaker', 'legacy_event_speaker_title_check'),
        ('meeting', 'meeting_auto_end_check_pair_chk'),
        ('meeting', 'meeting_join_url_check'),
        ('meeting', 'meeting_provider_host_user_id_check'),
        ('meeting', 'meeting_provider_meeting_id_check'),
        ('meeting', 'meeting_recording_urls_not_empty_chk'),
        ('meeting_auto_end_check_outcome', 'meeting_auto_end_check_outcome_display_name_check'),
        ('meeting_provider', 'meeting_provider_display_name_check'),
        ('notification', 'notification_delivery_attempts_chk'),
        ('notification', 'notification_delivery_status_chk'),
        ('notification', 'notification_error_check'),
        ('notification', 'notification_next_delivery_attempt_at_chk'),
        ('notification_category', 'notification_category_display_name_check'),
        ('notification_kind', 'notification_kind_name_check'),
        ('payment_job', 'payment_job_attempt_count_check'),
        ('payment_job', 'payment_job_claim_chk'),
        ('payment_job', 'payment_job_completed_chk'),
        ('payment_job', 'payment_job_failure_message_check'),
        ('payment_job', 'payment_job_idempotency_key_check'),
        ('payment_job', 'payment_job_kind_chk'),
        ('payment_job', 'payment_job_recovery_chk'),
        ('payment_job', 'payment_job_recovery_note_check'),
        ('payment_job', 'payment_job_recovery_reference_check'),
        ('payment_job', 'payment_job_status_chk'),
        ('payment_provider', 'payment_provider_display_name_check'),
        (
            'payment_provider_tax_location',
            'payment_provider_tax_location_connected_seller_id_check'
        ),
        ('payment_provider_tax_location', 'payment_provider_tax_location_fingerprint_check'),
        (
            'payment_provider_tax_location',
            'payment_provider_tax_location_provider_tax_location_id_check'
        ),
        ('payment_provider_tax_product', 'payment_provider_tax_product_connected_seller_id_check'),
        ('payment_provider_tax_product', 'payment_provider_tax_product_fingerprint_check'),
        (
            'payment_provider_tax_product',
            'payment_provider_tax_product_provider_tax_location_id_check'
        ),
        (
            'payment_provider_tax_product',
            'payment_provider_tax_product_provider_tax_product_id_check'
        ),
        ('payment_provider_tax_product', 'payment_provider_tax_product_tax_code_check'),
        ('payment_provider_tax_product', 'payment_provider_tax_product_title_check'),
        ('region', 'region_name_check'),
        ('region', 'region_normalized_name_check'),
        ('session', 'session_check'),
        ('session', 'session_description_check'),
        ('session', 'session_location_check'),
        ('session', 'session_meeting_conflict_chk'),
        ('session', 'session_meeting_error_check'),
        ('session', 'session_meeting_join_instructions_check'),
        ('session', 'session_meeting_join_url_check'),
        ('session', 'session_meeting_provider_host_user_check'),
        ('session', 'session_meeting_provider_required_chk'),
        ('session', 'session_meeting_recording_url_check'),
        ('session', 'session_meeting_requested_times_chk'),
        ('session', 'session_name_check'),
        ('session_proposal', 'session_proposal_check'),
        ('session_proposal', 'session_proposal_description_check'),
        ('session_proposal', 'session_proposal_title_check'),
        ('session_proposal_level', 'session_proposal_level_display_name_check'),
        ('session_proposal_status', 'session_proposal_status_display_name_check'),
        ('site', 'site_copyright_notice_check'),
        ('site', 'site_description_check'),
        ('site', 'site_favicon_url_check'),
        ('site', 'site_footer_logo_url_check'),
        ('site', 'site_header_logo_url_check'),
        ('site', 'site_og_image_url_check'),
        ('site', 'site_title_check'),
        ('"user"', 'user_auth_hash_check'),
        ('"user"', 'user_bio_check'),
        ('"user"', 'user_bluesky_url_check'),
        ('"user"', 'user_city_check'),
        ('"user"', 'user_company_check'),
        ('"user"', 'user_country_check'),
        ('"user"', 'user_email_check'),
        ('"user"', 'user_facebook_url_check'),
        ('"user"', 'user_github_url_check'),
        ('"user"', 'user_linkedin_url_check'),
        ('"user"', 'user_password_check'),
        ('"user"', 'user_photo_url_check'),
        ('"user"', 'user_registration_status_check'),
        ('"user"', 'user_timezone_check'),
        ('"user"', 'user_title_check'),
        ('"user"', 'user_twitter_url_check'),
        ('"user"', 'user_username_check'),
        ('"user"', 'user_website_url_check'),
        ('user_badge', 'user_badge_active_user_chk'),
        ('user_badge', 'user_badge_display_order_check'),
        ('user_badge', 'user_badge_identity_chk'),
        ('user_badge', 'user_badge_revocation_reason_check'),
        ('user_badge', 'user_badge_snapshot_check'),
        ('user_badge', 'user_badge_status_list_index_check')
    $$,
    'Check constraints should match expected tables and names'
);

-- Test: admission offers should require a ticket tier
select col_not_null('admission_offer', 'event_ticket_type_id');

-- Test: admission offer sources should match expected values
select results_eq(
    $$
        select (regexp_matches(pg_get_constraintdef(oid), $re$'([^']+)'$re$, 'g'))[1]
        from pg_constraint
        where conname = 'admission_offer_source_chk'
    $$,
    $$ values
        ('approval'),
        ('organizer_invitation'),
        ('waitlist')
    $$,
    'Admission offer sources should match expected values'
);

-- Test: admission offer statuses should match expected values
select results_eq(
    $$
        select (regexp_matches(pg_get_constraintdef(oid), $re$'([^']+)'$re$, 'g'))[1]
        from pg_constraint
        where conname = 'admission_offer_status_chk'
    $$,
    $$ values
        ('canceled'),
        ('checkout_pending'),
        ('completed'),
        ('declined'),
        ('expired'),
        ('pending')
    $$,
    'Admission offer statuses should match expected values'
);

-- Test: event table should keep its required defaults
select col_default_is('event', 'cohosts_revision', '0');
select col_not_null('event', 'cohosts_revision');
select col_default_is('event', 'meeting_recording_published', 'false');
select col_not_null('event', 'meeting_recording_published');

-- Test: event invitation requests may defer the ticket tier to organizer approval
select col_is_null('event_invitation_request', 'event_ticket_type_id');

-- Test: event UTM view counters should default to empty attribution values
select col_default_is('event_views_utm', 'utm_campaign', '');
select col_default_is('event_views_utm', 'utm_medium', '');
select col_default_is('event_views_utm', 'utm_source', '');

-- Test: event waitlist rows should always belong to a ticket tier
select col_not_null('event_waitlist', 'event_ticket_type_id');

-- Test: event survey table expected defaults exist
select col_default_is('event_survey', 'anonymous', 'true');
select col_default_is('event_survey', 'audience', 'confirmed');
select col_default_is('event_survey', 'questions', '[]');
select col_default_is('event_survey', 'revision', '1');
select col_default_is('event_survey', 'status', 'draft');

-- Test: group external payments should be required and disabled by default
select col_not_null('group', 'external_payments_enabled');
select col_default_is('group', 'external_payments_enabled', 'false');

-- Test: session table should keep its required defaults
select col_default_is('session', 'meeting_recording_published', 'false');
select col_not_null('session', 'meeting_recording_published');

-- Test: event attendee statuses should match expected values
select col_default_is('event_attendee', 'check_in_code', 'gen_random_uuid()');
select col_not_null('event_attendee', 'check_in_code');
select results_eq(
    $$
        select (regexp_matches(pg_get_constraintdef(oid), $re$'([^']+)'$re$, 'g'))[1]
        from pg_constraint
        where conname = 'event_attendee_status_chk'
    $$,
    $$ values
        ('attendance-canceled'),
        ('confirmed'),
        ('invitation-canceled'),
        ('invitation-pending'),
        ('invitation-rejected'),
        ('registration-questions-pending')
    $$,
    'Event attendee statuses should match expected values'
);

-- Test: event purchase statuses should match expected values
select col_is_null('event_purchase', 'currency_code');

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
        ('refund-recovery-pending'),
        ('refund-requested'),
        ('refunded')
    $$,
    'Event purchase statuses should match expected values'
);

-- Test: event tax choices should have stable defaults
select col_not_null('event', 'manual_tax_rate_ids');
select col_default_is('event', 'manual_tax_rate_ids', array[]::text[]);
select col_default_is('event', 'tax_behavior', 'inclusive');
select col_default_is('event', 'tax_calculation_mode', 'automatic');

-- Test: purchase charge model should default to free
select col_default_is('event_purchase', 'charge_model', 'ocg-free');

-- Test: event purchase provisional fee should be required and default to zero
select col_not_null('event_purchase', 'provisional_platform_fee_amount_minor');
select col_default_is('event_purchase', 'provisional_platform_fee_amount_minor', '0');

-- Test: event purchase refund kinds should match expected values
select results_eq(
    $$
        select (regexp_matches(pg_get_constraintdef(oid), $re$'([^']+)'$re$, 'g'))[1]
        from pg_constraint
        where conname = 'event_purchase_refund_kind_check'
    $$,
    $$ values
        ('attendance-cancellation'),
        ('automatic-unfulfillable-checkout'),
        ('event-cancellation'),
        ('refund-request-approval')
    $$,
    'Event purchase refund kinds should match expected values'
);

-- Test: event purchase refund statuses should match expected values
select results_eq(
    $$
        select (regexp_matches(pg_get_constraintdef(oid), $re$'([^']+)'$re$, 'g'))[1]
        from pg_constraint
        where conname = 'event_purchase_refund_status_check'
    $$,
    $$ values
        ('finalized'),
        ('provider-failed'),
        ('provider-pending'),
        ('provider-succeeded')
    $$,
    'Event purchase refund statuses should match expected values'
);

-- Test: payment job kinds should match expected values
select results_eq(
    $$
        select (regexp_matches(pg_get_constraintdef(oid), $re$'([^']+)'$re$, 'g'))[1]
        from pg_constraint
        where conname = 'payment_job_kind_chk'
    $$,
    $$ values
        ('event-purchase-application-fee-adjustment'),
        ('event-purchase-credit-note'),
        ('event-purchase-refund')
    $$,
    'Payment job kinds should match expected values'
);

-- Test: payment job statuses should match expected values
select results_eq(
    $$
        select (regexp_matches(pg_get_constraintdef(oid), $re$'([^']+)'$re$, 'g'))[1]
        from pg_constraint
        where conname = 'payment_job_status_chk'
    $$,
    $$ values
        ('completed'),
        ('failed'),
        ('pending'),
        ('processing')
    $$,
    'Payment job statuses should match expected values'
);

-- Test: event refund request statuses should match expected values
select results_eq(
    $$
        select (regexp_matches(pg_get_constraintdef(oid), $re$'([^']+)'$re$, 'g'))[1]
        from pg_constraint
        where conname = 'event_refund_request_status_check'
    $$,
    $$ values
        ('approved'),
        ('approving'),
        ('pending'),
        ('rejected')
    $$,
    'Event refund request statuses should match expected values'
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

-- Test: event co-host statuses should match expected values
select results_eq(
    'select * from event_cohost_status order by event_cohost_status_id',
    $$ values
        ('approved', 'Approved'),
        ('canceled', 'Canceled'),
        ('event-canceled', 'Event canceled'),
        ('event-deleted', 'Event deleted'),
        ('pending', 'Pending'),
        ('rejected', 'Rejected'),
        ('removed', 'Removed')
    $$,
    'Event co-host statuses should exist'
);

-- Test: inbox conversation statuses should match expected values
select results_eq(
    'select * from inbox_conversation_status order by inbox_conversation_status_id',
    $$ values
        ('answered', 'Answered'),
        ('closed', 'Closed'),
        ('open', 'Open'),
        ('spam', 'Spam')
    $$,
    'Inbox conversation statuses should exist'
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

-- Test: notification categories should match expected values
select results_eq(
    'select notification_category_id, display_name, group_mutable from notification_category order by notification_category_id',
    $$ values
        ('attendee-activity', 'Attendee activity', false),
        ('badges', 'Badges', true),
        ('cohosting-updates', 'Co-hosting updates', false),
        ('event-reminders', 'Event reminders', true),
        ('event-surveys', 'Event surveys', true),
        ('group-announcements', 'Group announcements', true),
        ('group-inbox', 'Group inbox', false),
        ('new-events', 'New events', true),
        ('organizer-messages', 'Messages from event organizers', true),
        ('paid-event-setups', 'Paid event setups', false)
    $$,
    'Notification categories should exist'
);

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
    'select name, notification_category_id from notification_kind order by name',
    $$ values
        ('badge-awarded', 'badges'::text),
        ('badge-revoked', 'badges'::text),
        ('cfs-submission-updated', null::text),
        ('community-custom', null::text),
        ('community-team-invitation', null::text),
        ('email-verification', null::text),
        ('event-admission-offer-canceled', null::text),
        ('event-admission-offer-created', null::text),
        ('event-admission-offer-declined', 'attendee-activity'::text),
        ('event-attendance-canceled', null::text),
        ('event-canceled', null::text),
        ('event-cohost-invitation', null::text),
        ('event-cohost-removed', 'cohosting-updates'::text),
        ('event-cohost-responded', 'cohosting-updates'::text),
        ('event-custom', 'organizer-messages'::text),
        ('event-external-payment-expired', null::text),
        ('event-external-payment-pending', null::text),
        ('event-external-payment-reminder', null::text),
        ('event-paid-configured', 'paid-event-setups'::text),
        ('event-published', 'new-events'::text),
        ('event-refund-approved', null::text),
        ('event-refund-rejected', null::text),
        ('event-refund-requested', null::text),
        ('event-reminder', 'event-reminders'::text),
        ('event-rescheduled', null::text),
        ('event-series-canceled', null::text),
        ('event-series-published', 'new-events'::text),
        ('event-survey-opened', 'event-surveys'::text),
        ('event-ticket-request-approved', null::text),
        ('event-ticket-waitlist-offer', null::text),
        ('event-waitlist-joined', null::text),
        ('event-waitlist-left', null::text),
        ('event-welcome', null::text),
        ('group-custom', 'group-announcements'::text),
        ('group-team-invitation', null::text),
        ('group-welcome', null::text),
        ('inbox-message-received', 'group-inbox'::text),
        ('inbox-reply-received', null::text),
        ('session-proposal-co-speaker-invitation', null::text),
        ('speaker-series-welcome', null::text),
        ('speaker-welcome', null::text)
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

-- Test: utm mediums should match expected values
select results_eq(
    'select * from utm_medium order by utm_medium_id',
    $$ values
        ('affiliate'),
        ('cpc'),
        ('display'),
        ('email'),
        ('organic'),
        ('qr'),
        ('referral'),
        ('sms'),
        ('social'),
        ('video')
    $$,
    'Utm mediums should exist'
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
        ('admin', 'group.badges.write'),
        ('admin', 'group.check-ins.write'),
        ('admin', 'group.events.write'),
        ('admin', 'group.inbox.write'),
        ('admin', 'group.members.write'),
        ('admin', 'group.read'),
        ('admin', 'group.settings.write'),
        ('admin', 'group.sponsors.write'),
        ('admin', 'group.team.write'),
        ('groups-manager', 'group.badges.write'),
        ('groups-manager', 'group.check-ins.write'),
        ('groups-manager', 'group.events.write'),
        ('groups-manager', 'group.inbox.write'),
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
        ('group.badges.write', 'Badges Write'),
        ('group.check-ins.write', 'Check-Ins Write'),
        ('group.events.write', 'Events Write'),
        ('group.inbox.write', 'Inbox Write'),
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
        ('check-in-manager', 'Check-In Manager'),
        ('events-manager', 'Events Manager'),
        ('viewer', 'Viewer')
    $$,
    'Group roles should exist'
);

-- Test: group role to group permission mapping should match expected values
select results_eq(
    'select group_permission_id, group_role_id from group_role_group_permission order by group_permission_id, group_role_id',
    $$ values
        ('group.badges.write', 'admin'),
        ('group.badges.write', 'events-manager'),
        ('group.check-ins.write', 'admin'),
        ('group.check-ins.write', 'check-in-manager'),
        ('group.check-ins.write', 'events-manager'),
        ('group.events.write', 'admin'),
        ('group.events.write', 'events-manager'),
        ('group.inbox.write', 'admin'),
        ('group.inbox.write', 'events-manager'),
        ('group.members.write', 'admin'),
        ('group.read', 'admin'),
        ('group.read', 'check-in-manager'),
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
