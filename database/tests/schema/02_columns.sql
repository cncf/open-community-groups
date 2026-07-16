-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(78);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: attachment columns should match expected
select columns_are('attachment', array[
    'attachment_id',
    'content_type',
    'created_at',
    'data',
    'file_name',
    'hash'
]);

-- Test: audit_log columns should match expected
select columns_are('audit_log', array[
    'audit_log_id',
    'action',
    'created_at',
    'resource_id',
    'resource_type',

    'actor_user_id',
    'actor_username',
    'alliance_id',
    'details',
    'event_id',
    'group_id'
]);

-- Test: auth_session columns should match expected
select columns_are('auth_session', array[
    'auth_session_id',
    'data',
    'expires_at'
]);

-- Test: api_token columns should match expected
select columns_are('api_token', array[
    'api_token_id',
    'created_at',
    'last_used_at',
    'name',
    'revoked_at',
    'scopes',
    'token_hash',
    'token_prefix',
    'user_id'
]);

-- Test: cfs_submission columns should match expected
select columns_are('cfs_submission', array[
    'cfs_submission_id',
    'created_at',
    'event_id',
    'session_proposal_id',
    'status_id',

    'action_required_message',
    'reviewed_by',
    'updated_at'
]);

-- Test: cfs_submission_label columns should match expected
select columns_are('cfs_submission_label', array[
    'cfs_submission_id',
    'created_at',
    'event_cfs_label_id'
]);

-- Test: cfs_submission_rating columns should match expected
select columns_are('cfs_submission_rating', array[
    'cfs_submission_id',
    'reviewer_id',
    'stars',

    'comments',
    'created_at',
    'updated_at'
]);

-- Test: cfs_submission_status columns should match expected
select columns_are('cfs_submission_status', array[
    'cfs_submission_status_id',
    'display_name'
]);

-- Test: coffee_meet_request columns should match expected
select columns_are('coffee_meet_request', array[
    'coffee_meet_request_id',
    'created_at',
    'message',
    'recipient_user_id',
    'requester_user_id'
]);

-- Test: coffee_meet_subscription columns should match expected
select columns_are('coffee_meet_subscription', array[
    'group_id',
    'user_id',
    'active',
    'created_at',
    'frequency',
    'last_suggestion_at',
    'next_suggestion_at',
    'updated_at'
]);

-- Test: coffee_meet_suggestion columns should match expected
select columns_are('coffee_meet_suggestion', array[
    'coffee_meet_suggestion_id',
    'created_at',
    'frequency',
    'group_id',
    'notification_enqueued_at',
    'subscriber_user_id',
    'suggested_for',
    'suggested_user_id'
]);

-- Test: alliance columns should match expected
select columns_are('alliance', array[
    'alliance_id',
    'active',
    'banner_mobile_url',
    'banner_url',
    'alliance_site_layout_id',
    'book_exchange_enabled',
    'created_at',
    'coffee_meet_enabled',
    'description',
    'display_name',
    'group_team_management_restricted',
    'logo_url',
    'mentorship_enabled',
    'mock_interviews_enabled',
    'name',

    'ad_banner_link_url',
    'ad_banner_url',
    'bluesky_url',
    'extra_links',
    'facebook_url',
    'flickr_url',
    'github_url',
    'instagram_url',
    'linkedin_url',
    'new_group_details',
    'og_image_url',
    'photos_urls',
    'report_public_enabled',
    'slack_url',
    'twitter_url',
    'website_url',
    'wechat_url',
    'youtube_url'
]);

-- Test: alliance_redirect_settings columns should match expected
select columns_are('alliance_redirect_settings', array[
    'alliance_id',

    'base_legacy_url'
]);

-- Test: alliance_site_layout columns should match expected
select columns_are('alliance_site_layout', array[
    'alliance_site_layout_id'
]);

-- Test: alliance_role columns should match expected
select columns_are('alliance_role', array[
    'alliance_role_id',
    'display_name'
]);

-- Test: alliance_permission columns should match expected
select columns_are('alliance_permission', array[
    'alliance_permission_id',
    'display_name'
]);

-- Test: alliance_role_alliance_permission columns should match expected
select columns_are('alliance_role_alliance_permission', array[
    'alliance_permission_id',
    'alliance_role_id'
]);

-- Test: alliance_role_group_permission columns should match expected
select columns_are('alliance_role_group_permission', array[
    'alliance_role_id',
    'group_permission_id'
]);

-- Test: alliance_team columns should match expected
select columns_are('alliance_team', array[
    'alliance_id',
    'accepted',
    'created_at',
    'role',
    'user_id'
]);

-- Test: alliance_views columns should match expected
select columns_are('alliance_views', array[
    'alliance_id',
    'day',
    'total'
]);

-- Test: custom_notification columns should match expected
select columns_are('custom_notification', array[
    'custom_notification_id',
    'created_at',
    'created_by',
    'event_id',
    'group_id',
    'subject',
    'body'
]);

-- Test: email_verification_code columns should match expected
select columns_are('email_verification_code', array[
    'email_verification_code_id',
    'created_at',
    'user_id'
]);

-- Test: event columns should match expected
select columns_are('event', array[
    'event_id',
    'canceled',
    'created_at',
    'deleted',
    'description',
    'event_category_id',
    'event_kind_id',
    'event_reminder_enabled',
    'group_id',
    'name',
    'published',
    'slug',
    'test_event',
    'timezone',
    'tsdoc',

    'attendee_approval_required',
    'banner_mobile_url',
    'banner_url',
    'capacity',
    'cfs_description',
    'cfs_enabled',
    'cfs_ends_at',
    'cfs_starts_at',
    'created_by',
    'deleted_at',
    'description_short',
    'ends_at',
    'event_reminder_evaluated_for_starts_at',
    'event_reminder_sent_at',
    'event_series_id',
    'legacy_id',
    'legacy_url',
    'location',
    'logo_url',
    'luma_url',
    'meeting_error',
    'meeting_hosts',
    'meeting_in_sync',
    'meeting_join_instructions',
    'meeting_join_url',
    'meeting_provider_host_user',
    'meeting_provider_id',
    'meeting_recording_published',
    'meeting_recording_requested',
    'meeting_recording_url',
    'meeting_requested',
    'meeting_sync_claimed_at',
    'meetup_url',
    'payment_currency_code',
    'photos_urls',
    'published_at',
    'published_by',
    'registration_ends_at',
    'registration_questions',
    'registration_required',
    'registration_starts_at',
    'starts_at',
    'tags',
    'venue_address',
    'venue_city',
    'venue_country_code',
    'venue_country_name',
    'venue_name',
    'venue_state',
    'venue_zip_code',
    'waitlist_enabled'
]);

select is(
    (
        select column_default
        from information_schema.columns
        where table_schema = 'public'
        and table_name = 'event'
        and column_name = 'meeting_recording_published'
    ),
    'false',
    'Event meeting recording publication should default to false'
);

select is(
    (
        select is_nullable
        from information_schema.columns
        where table_schema = 'public'
        and table_name = 'event'
        and column_name = 'meeting_recording_published'
    ),
    'NO',
    'Event meeting recording publication should be required'
);

-- Test: event_invitation_request columns should match expected
select columns_are('event_invitation_request', array[
    'event_id',
    'user_id',
    'created_at',
    'status',

    'registration_answers',
    'reviewed_at',
    'reviewed_by'
]);

-- Test: event_attendee columns should match expected
select columns_are('event_attendee', array[
    'event_id',
    'user_id',
    'checked_in',
    'created_at',
    'manually_invited',
    'status',

    'checked_in_at',
    'registration_answers'
]);

-- Test: event_category columns should match expected
select columns_are('event_category', array[
    'event_category_id',
    'alliance_id',
    'created_at',
    'name',
    'order',
    'slug'
]);

-- Test: event_series columns should match expected
select columns_are('event_series', array[
    'event_series_id',
    'created_at',
    'group_id',
    'recurrence_additional_occurrences',
    'recurrence_anchor_starts_at',
    'recurrence_pattern',
    'timezone',

    'created_by'
]);

-- Test: event_discount_code columns should match expected
select columns_are('event_discount_code', array[
    'event_discount_code_id',
    'active',
    'code',
    'created_at',
    'event_id',
    'kind',
    'title',
    'updated_at',

    'available',
    'available_override_active',
    'amount_minor',
    'ends_at',
    'percentage',
    'starts_at',
    'total_available'
]);

-- Test: event_host columns should match expected
select columns_are('event_host', array[
    'event_id',
    'user_id',
    'created_at'
]);

-- Test: event_kind columns should match expected
select columns_are('event_kind', array[
    'event_kind_id',
    'display_name'
]);

-- Test: event_organizer columns should match expected
select columns_are('event_organizer', array[
    'event_id',
    'user_id',

    'order'
]);

-- Test: event_purchase columns should match expected
select columns_are('event_purchase', array[
    'event_purchase_id',
    'amount_minor',
    'created_at',
    'currency_code',
    'discount_amount_minor',
    'event_id',
    'event_ticket_type_id',
    'status',
    'ticket_title',
    'updated_at',
    'user_id',

    'completed_at',
    'discount_code',
    'hold_expires_at',
    'payment_provider_id',
    'provider_checkout_session_id',
    'provider_checkout_url',
    'provider_payment_reference',
    'refunded_at',
    'event_discount_code_id'
]);

-- Test: event_refund_request columns should match expected
select columns_are('event_refund_request', array[
    'event_refund_request_id',
    'created_at',
    'event_purchase_id',
    'requested_by_user_id',
    'status',
    'updated_at',

    'requested_reason',
    'review_note',
    'reviewed_at',
    'reviewed_by_user_id'
]);

-- Test: event_ticket_price_window columns should match expected
select columns_are('event_ticket_price_window', array[
    'event_ticket_price_window_id',
    'amount_minor',
    'created_at',
    'event_ticket_type_id',
    'updated_at',

    'ends_at',
    'starts_at'
]);

-- Test: event_ticket_type columns should match expected
select columns_are('event_ticket_type', array[
    'event_ticket_type_id',
    'active',
    'created_at',
    'event_id',
    'order',
    'seats_total',
    'title',
    'updated_at',

    'description'
]);

-- Test: event_cfs_label columns should match expected
select columns_are('event_cfs_label', array[
    'color',
    'created_at',
    'event_id',
    'event_cfs_label_id',
    'name'
]);

-- Test: event_speaker columns should match expected
select columns_are('event_speaker', array[
    'created_at',
    'event_id',
    'featured',
    'user_id'
]);

-- Test: event_sponsor columns should match expected
select columns_are('event_sponsor', array[
    'created_at',
    'event_id',
    'group_sponsor_id',
    'level'
]);

-- Test: event_views columns should match expected
select columns_are('event_views', array[
    'event_id',
    'day',
    'total'
]);

-- Test: event_waitlist columns should match expected
select columns_are('event_waitlist', array[
    'event_id',
    'user_id',
    'created_at'
]);

-- Test: meeting columns should match expected
select columns_are('meeting', array[
    'meeting_id',
    'created_at',
    'join_url',
    'meeting_provider_id',
    'provider_meeting_id',

    'auto_end_check_at',
    'auto_end_check_claimed_at',
    'auto_end_check_outcome',
    'event_id',
    'password',
    'provider_host_user_id',
    'recording_publish_checked_at',
    'recording_publish_claimed_at',
    'recording_publish_drive_file_id',
    'recording_publish_error',
    'recording_publish_url',
    'recording_urls',
    'session_id',
    'sync_claimed_at',
    'updated_at'
]);

-- Test: meeting_auto_end_check_outcome columns should match expected
select columns_are('meeting_auto_end_check_outcome', array[
    'meeting_auto_end_check_outcome_id',
    'display_name'
]);

-- Test: meeting_provider columns should match expected
select columns_are('meeting_provider', array[
    'meeting_provider_id',
    'display_name'
]);

-- Test: group columns should match expected
select columns_are('group', array[
    'group_id',
    'active',
    'alliance_id',
    'created_at',
    'deleted',
    'group_category_id',
    'group_site_layout_id',
    'name',
    'slug',
    'tsdoc',

    'banner_mobile_url',
    'banner_url',
    'bluesky_url',
    'book_exchange_enabled',
    'city',
    'coffee_meet_enabled',
    'country_code',
    'country_name',
    'deleted_at',
    'description',
    'description_short',
    'discord_url',
    'event_defaults',
    'extra_links',
    'facebook_url',
    'flickr_url',
    'google_photos_url',
    'github_url',
    'instagram_url',
    'legacy_id',
    'legacy_url',
    'linkedin_url',
    'location',
    'logo_url',
    'membership_approval_required',
    'mentorship_enabled',
    'mock_interviews_enabled',
    'og_image_url',
    'payment_recipient',
    'photos_urls',
    'region_id',
    'report_public_enabled',
    'slack_url',
    'slug_pretty',
    'state',
    'substack_url',
    'tags',
    'twitter_url',
    'website_url',
    'whatsapp_url',
    'wechat_url',
    'youtube_url'
]);

-- Test: group_category columns should match expected
select columns_are('group_category', array[
    'group_category_id',
    'alliance_id',
    'created_at',
    'name',
    'normalized_name',

    'order'
]);

-- Test: group_join_request columns should match expected
select columns_are('group_join_request', array[
    'group_id',
    'user_id',
    'status',
    'created_at',
    'reviewed_at',
    'reviewed_by'
]);

-- Test: group_member columns should match expected
select columns_are('group_member', array[
    'group_id',
    'user_id',
    'created_at'
]);

select columns_are('group_member_phone_request', array[
    'group_member_phone_request_id',
    'group_id',
    'requester_user_id',
    'recipient_user_id',
    'status',
    'created_at',
    'updated_at'
]);

-- Test: group_member_spotlight columns should match expected
select columns_are('group_member_spotlight', array[
    'group_member_spotlight_id',
    'group_id',
    'user_id',
    'created_by',
    'title',
    'story',
    'image_url',
    'link_url',
    'featured',
    'published',
    'created_at',
    'updated_at'
]);

-- Test: group_role columns should match expected
select columns_are('group_role', array[
    'group_role_id',
    'display_name'
]);

-- Test: group_permission columns should match expected
select columns_are('group_permission', array[
    'group_permission_id',
    'display_name'
]);

-- Test: group_role_group_permission columns should match expected
select columns_are('group_role_group_permission', array[
    'group_permission_id',
    'group_role_id'
]);

-- Test: group_site_layout columns should match expected
select columns_are('group_site_layout', array[
    'group_site_layout_id'
]);

-- Test: group_sponsor columns should match expected
select columns_are('group_sponsor', array[
    'group_sponsor_id',
    'created_at',
    'featured',
    'group_id',
    'logo_url',
    'name',

    'website_url'
]);

-- Test: group_store_item columns should match expected
select columns_are('group_store_item', array[
    'group_store_item_id',
    'group_id',
    'created_by',
    'name',
    'description',
    'image_url',
    'price_minor',
    'currency_code',
    'inventory_count',
    'checkout_url',
    'featured',
    'active',
    'created_at',
    'updated_at'
]);

-- Test: group_team columns should match expected
select columns_are('group_team', array[
    'group_id',
    'user_id',
    'accepted',
    'created_at',
    'role',

    'order'
]);

-- Test: group_views columns should match expected
select columns_are('group_views', array[
    'group_id',
    'day',
    'total'
]);

-- Test: images columns should match expected
select columns_are('images', array[
    'file_name',
    'content_type',
    'created_at',
    'created_by',
    'data'
]);

-- Test: session columns should match expected
select columns_are('session', array[
    'session_id',
    'created_at',
    'event_id',
    'name',
    'session_kind_id',
    'starts_at',

    'cfs_submission_id',
    'description',
    'ends_at',
    'location',
    'meeting_error',
    'meeting_hosts',
    'meeting_in_sync',
    'meeting_join_instructions',
    'meeting_join_url',
    'meeting_provider_host_user',
    'meeting_provider_id',
    'meeting_recording_published',
    'meeting_recording_url',
    'meeting_requested',
    'meeting_sync_claimed_at'
]);

select is(
    (
        select column_default
        from information_schema.columns
        where table_schema = 'public'
        and table_name = 'session'
        and column_name = 'meeting_recording_published'
    ),
    'false',
    'Session meeting recording publication should default to false'
);

select is(
    (
        select is_nullable
        from information_schema.columns
        where table_schema = 'public'
        and table_name = 'session'
        and column_name = 'meeting_recording_published'
    ),
    'NO',
    'Session meeting recording publication should be required'
);

-- Test: session_kind columns should match expected
select columns_are('session_kind', array[
    'session_kind_id',
    'display_name'
]);

-- Test: session_proposal columns should match expected
select columns_are('session_proposal', array[
    'created_at',
    'description',
    'duration',
    'session_proposal_id',
    'session_proposal_level_id',
    'title',
    'user_id',

    'co_speaker_user_id',
    'session_proposal_status_id',
    'updated_at'
]);

-- Test: session_proposal_level columns should match expected
select columns_are('session_proposal_level', array[
    'session_proposal_level_id',
    'display_name'
]);

-- Test: session_proposal_status columns should match expected
select columns_are('session_proposal_status', array[
    'session_proposal_status_id',
    'display_name'
]);

-- Test: session_speaker columns should match expected
select columns_are('session_speaker', array[
    'created_at',
    'featured',
    'session_id',
    'user_id'
]);

-- Test: legacy_event_host columns should match expected
select columns_are('legacy_event_host', array[
    'legacy_event_host_id',
    'event_id',

    'bio',
    'name',
    'photo_url',
    'title'
]);

-- Test: legacy_event_speaker columns should match expected
select columns_are('legacy_event_speaker', array[
    'legacy_event_speaker_id',
    'event_id',

    'bio',
    'name',
    'photo_url',
    'title'
]);

-- Test: notification columns should match expected
select columns_are('notification', array[
    'notification_id',
    'created_at',
    'delivery_attempts',
    'delivery_status',
    'kind',
    'user_id',

    'delivery_claimed_at',
    'error',
    'notification_template_data_id',
    'processed_at'
]);

-- Test: notification_attachment columns should match expected
select columns_are('notification_attachment', array[
    'notification_id',
    'attachment_id'
]);

-- Test: notification_kind columns should match expected
select columns_are('notification_kind', array[
    'notification_kind_id',

    'name',
    'optional_notification'
]);

-- Test: notification_template_data columns should match expected
select columns_are('notification_template_data', array[
    'notification_template_data_id',
    'created_at',
    'data',
    'hash'
]);

-- Test: payment_provider columns should match expected
select columns_are('payment_provider', array[
    'payment_provider_id',
    'display_name'
]);

-- Test: region columns should match expected
select columns_are('region', array[
    'region_id',
    'alliance_id',
    'created_at',
    'name',
    'normalized_name',

    'order'
]);

-- Test: site columns should match expected
select columns_are('site', array[
    'site_id',
    'created_at',
    'description',
    'theme',
    'title',

    'copyright_notice',
    'favicon_url',
    'footer_logo_url',
    'header_logo_url',
    'og_image_url'
]);

-- Test: user columns should match expected
select columns_are('user', array[
    'user_id',
    'auth_hash',
    'created_at',
    'email',
    'email_verified',
    'tsdoc',
    'username',

    'bio',
    'bluesky_url',
    'book_exchange_enabled',
    'book_exchange_books',
    'city',
    'coffee_meet_enabled',
    'company',
    'country',
    'facebook_url',
    'github_url',
    'interests',
    'legacy_id',
    'linkedin_url',
    'mentorship_businesses',
    'mentorship_individuals',
    'mentorship_note',
    'mentorship_price',
    'name',
    'optional_notifications_enabled',
    'password',
    'platform_admin',
    'photo_url',
    'phone_country_code',
    'phone_number',
    'provider',
    'registration_status',
    'substack_url',
    'timezone',
    'title',
    'twitter_url',
    'website_url',
    'youtube_url'
]);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
