-- Tests database primary and foreign keys.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: primary keys should match the expected snapshot
select bag_eq(
    $$
        select
            c.conrelid::regclass::text as table_name,
            (
                select array_agg(a.attname::text order by k.ord)
                from unnest(c.conkey) with ordinality as k(attnum, ord)
                join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
            ) as column_names
        from pg_constraint c
        where c.connamespace = 'public'::regnamespace
        and c.contype = 'p'
        and c.conrelid::regclass::text not in ('version_functions', 'version_schema')
        and not exists (
            select 1
            from pg_depend d
            where d.classid = 'pg_class'::regclass
            and d.objid = c.conrelid
            and d.deptype = 'e'
        )
    $$,
    $$ values
        ('admission_offer', array['admission_offer_id']),
        ('attachment', array['attachment_id']),
        ('audit_log', array['audit_log_id']),
        ('auth_session', array['auth_session_id']),
        ('badge', array['badge_id']),
        ('badge_artwork', array['badge_artwork_id']),
        ('badge_award_job', array['badge_award_job_id']),
        ('badge_award_job_recipient', array['badge_award_job_id', 'position']),
        ('badge_status_list', array['badge_status_list_id']),
        ('cfs_submission', array['cfs_submission_id']),
        ('cfs_submission_label', array['cfs_submission_id', 'event_label_id']),
        ('cfs_submission_rating', array['cfs_submission_id', 'reviewer_id']),
        ('cfs_submission_status', array['cfs_submission_status_id']),
        ('community', array['community_id']),
        ('community_permission', array['community_permission_id']),
        ('community_redirect_settings', array['community_id']),
        ('community_role', array['community_role_id']),
        ('community_role_community_permission', array['community_permission_id', 'community_role_id']),
        ('community_role_group_permission', array['community_role_id', 'group_permission_id']),
        ('community_site_layout', array['community_site_layout_id']),
        ('community_team', array['community_id', 'user_id']),
        ('custom_notification', array['custom_notification_id']),
        ('email_verification_code', array['email_verification_code_id']),
        ('event', array['event_id']),
        ('event_attendee', array['event_id', 'user_id']),
        ('event_category', array['event_category_id']),
        ('event_cohost', array['event_id', 'group_id']),
        ('event_cohost_status', array['event_cohost_status_id']),
        ('event_discount_code', array['event_discount_code_id']),
        ('event_host', array['event_id', 'user_id']),
        ('event_invitation_request', array['event_id', 'user_id']),
        ('event_kind', array['event_kind_id']),
        ('event_label', array['event_label_id']),
        ('event_organizer', array['event_id', 'user_id']),
        ('event_purchase', array['event_purchase_id']),
        ('event_purchase_application_fee_adjustment', array['event_purchase_application_fee_adjustment_id']),
        ('event_purchase_credit_note', array['event_purchase_credit_note_id']),
        ('event_purchase_refund', array['event_purchase_refund_id']),
        ('event_refund_request', array['event_refund_request_id']),
        ('event_series', array['event_series_id']),
        ('event_speaker', array['event_id', 'user_id']),
        ('event_sponsor', array['group_sponsor_id', 'event_id']),
        ('event_survey', array['event_survey_id']),
        ('event_survey_response', array['event_survey_id', 'user_id']),
        ('event_ticket_price_window', array['event_ticket_price_window_id']),
        ('event_ticket_type', array['event_ticket_type_id']),
        ('event_waitlist', array['event_id', 'user_id']),
        ('external_payments_config', array['singleton']),
        ('"group"', array['group_id']),
        ('group_category', array['group_category_id']),
        ('group_member', array['group_id', 'user_id']),
        ('group_permission', array['group_permission_id']),
        ('group_role', array['group_role_id']),
        ('group_role_group_permission', array['group_permission_id', 'group_role_id']),
        ('group_site_layout', array['group_site_layout_id']),
        ('group_sponsor', array['group_sponsor_id']),
        ('group_team', array['group_id', 'user_id']),
        ('images', array['file_name']),
        ('inbox_conversation', array['inbox_conversation_id']),
        ('inbox_conversation_status', array['inbox_conversation_status_id']),
        ('inbox_message', array['inbox_message_id']),
        ('legacy_event_host', array['legacy_event_host_id']),
        ('legacy_event_speaker', array['legacy_event_speaker_id']),
        ('meeting', array['meeting_id']),
        ('meeting_auto_end_check_outcome', array['meeting_auto_end_check_outcome_id']),
        ('meeting_provider', array['meeting_provider_id']),
        ('notification', array['notification_id']),
        ('notification_attachment', array['notification_id', 'attachment_id']),
        ('notification_category', array['notification_category_id']),
        ('notification_kind', array['notification_kind_id']),
        ('notification_template_data', array['notification_template_data_id']),
        ('payment_job', array['payment_job_id']),
        ('payment_provider', array['payment_provider_id']),
        ('payment_provider_tax_location', array['payment_provider_tax_location_id']),
        ('payment_provider_tax_product', array['payment_provider_tax_product_id']),
        ('region', array['region_id']),
        ('session', array['session_id']),
        ('session_kind', array['session_kind_id']),
        ('session_label', array['session_id', 'event_label_id']),
        ('session_proposal', array['session_proposal_id']),
        ('session_proposal_level', array['session_proposal_level_id']),
        ('session_proposal_status', array['session_proposal_status_id']),
        ('session_speaker', array['session_id', 'user_id']),
        ('site', array['site_id']),
        ('"user"', array['user_id']),
        ('user_badge', array['user_badge_id']),
        ('user_group_notification_mute', array['user_id', 'group_id']),
        ('user_notification_opt_out', array['user_id', 'notification_category_id']),
        ('utm_medium', array['utm_medium_id'])
    $$,
    'Primary keys should match expected tables and columns'
);

-- Test: foreign keys should match the expected snapshot
select bag_eq(
    $$
        select
            c.conrelid::regclass::text as table_name,
            (
                select array_agg(a.attname::text order by k.ord)
                from unnest(c.conkey) with ordinality as k(attnum, ord)
                join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
            ) as column_names,
            c.confrelid::regclass::text as referenced_table_name,
            (
                select array_agg(a.attname::text order by k.ord)
                from unnest(c.confkey) with ordinality as k(attnum, ord)
                join pg_attribute a on a.attrelid = c.confrelid and a.attnum = k.attnum
            ) as referenced_column_names,
            case c.confdeltype
                when 'a' then 'no action'
                when 'c' then 'cascade'
                when 'd' then 'set default'
                when 'n' then 'set null' || coalesce(
                    ' (' || (
                        select string_agg(a.attname::text, ', ' order by k.ord)
                        from unnest(c.confdelsetcols) with ordinality as k(attnum, ord)
                        join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
                    ) || ')',
                    ''
                )
                when 'r' then 'restrict'
            end as on_delete
        from pg_constraint c
        where c.connamespace = 'public'::regnamespace
        and c.contype = 'f'
        and c.conrelid::regclass::text not in ('version_functions', 'version_schema')
        and not exists (
            select 1
            from pg_depend d
            where d.classid = 'pg_class'::regclass
            and d.objid = c.conrelid
            and d.deptype = 'e'
        )
    $$,
    $$ values
        (
            'admission_offer',
            array['event_discount_code_id'],
            'event_discount_code',
            array['event_discount_code_id'],
            'no action'
        ),
        (
            'admission_offer',
            array['event_id', 'event_discount_code_id'],
            'event_discount_code',
            array['event_id', 'event_discount_code_id'],
            'no action'
        ),
        (
            'admission_offer',
            array['event_id', 'event_ticket_type_id'],
            'event_ticket_type',
            array['event_id', 'event_ticket_type_id'],
            'no action'
        ),
        ('admission_offer', array['event_id'], 'event', array['event_id'], 'no action'),
        (
            'admission_offer',
            array['event_ticket_type_id'],
            'event_ticket_type',
            array['event_ticket_type_id'],
            'no action'
        ),
        ('admission_offer', array['organizer_user_id'], '"user"', array['user_id'], 'no action'),
        ('admission_offer', array['user_id'], '"user"', array['user_id'], 'no action'),
        ('badge', array['group_id'], '"group"', array['group_id'], 'no action'),
        ('badge_artwork', array['group_id'], '"group"', array['group_id'], 'no action'),
        ('badge_award_job', array['actor_user_id'], '"user"', array['user_id'], 'set null'),
        ('badge_award_job', array['badge_id'], 'badge', array['badge_id'], 'set null'),
        ('badge_award_job', array['community_id'], 'community', array['community_id'], 'no action'),
        ('badge_award_job', array['event_id'], 'event', array['event_id'], 'set null'),
        ('badge_award_job', array['group_id'], '"group"', array['group_id'], 'no action'),
        (
            'badge_award_job_recipient',
            array['badge_award_job_id'],
            'badge_award_job',
            array['badge_award_job_id'],
            'cascade'
        ),
        ('badge_award_job_recipient', array['user_id'], '"user"', array['user_id'], 'set null'),
        ('badge_status_list', array['group_id'], '"group"', array['group_id'], 'no action'),
        ('cfs_submission', array['event_id'], 'event', array['event_id'], 'no action'),
        ('cfs_submission', array['reviewed_by'], '"user"', array['user_id'], 'no action'),
        (
            'cfs_submission',
            array['session_proposal_id'],
            'session_proposal',
            array['session_proposal_id'],
            'no action'
        ),
        (
            'cfs_submission',
            array['status_id'],
            'cfs_submission_status',
            array['cfs_submission_status_id'],
            'no action'
        ),
        (
            'cfs_submission_label',
            array['cfs_submission_id'],
            'cfs_submission',
            array['cfs_submission_id'],
            'cascade'
        ),
        (
            'cfs_submission_label',
            array['event_label_id'],
            'event_label',
            array['event_label_id'],
            'cascade'
        ),
        (
            'cfs_submission_rating',
            array['cfs_submission_id'],
            'cfs_submission',
            array['cfs_submission_id'],
            'cascade'
        ),
        ('cfs_submission_rating', array['reviewer_id'], '"user"', array['user_id'], 'no action'),
        (
            'community',
            array['community_site_layout_id'],
            'community_site_layout',
            array['community_site_layout_id'],
            'no action'
        ),
        (
            'community_redirect_settings',
            array['community_id'],
            'community',
            array['community_id'],
            'cascade'
        ),
        (
            'community_role_community_permission',
            array['community_permission_id'],
            'community_permission',
            array['community_permission_id'],
            'no action'
        ),
        (
            'community_role_community_permission',
            array['community_role_id'],
            'community_role',
            array['community_role_id'],
            'no action'
        ),
        (
            'community_role_group_permission',
            array['community_role_id'],
            'community_role',
            array['community_role_id'],
            'no action'
        ),
        (
            'community_role_group_permission',
            array['group_permission_id'],
            'group_permission',
            array['group_permission_id'],
            'no action'
        ),
        ('community_team', array['community_id'], 'community', array['community_id'], 'no action'),
        ('community_team', array['role'], 'community_role', array['community_role_id'], 'no action'),
        ('community_team', array['user_id'], '"user"', array['user_id'], 'no action'),
        ('community_views', array['community_id'], 'community', array['community_id'], 'set null'),
        (
            'custom_notification',
            array['community_id'],
            'community',
            array['community_id'],
            'cascade'
        ),
        ('custom_notification', array['created_by'], '"user"', array['user_id'], 'set null'),
        ('custom_notification', array['event_id'], 'event', array['event_id'], 'cascade'),
        ('custom_notification', array['group_id'], '"group"', array['group_id'], 'cascade'),
        ('email_verification_code', array['user_id'], '"user"', array['user_id'], 'cascade'),
        ('event', array['created_by'], '"user"', array['user_id'], 'set null'),
        (
            'event',
            array['event_category_id'],
            'event_category',
            array['event_category_id'],
            'no action'
        ),
        ('event', array['event_kind_id'], 'event_kind', array['event_kind_id'], 'no action'),
        ('event', array['event_series_id'], 'event_series', array['event_series_id'], 'no action'),
        ('event', array['group_id'], '"group"', array['group_id'], 'no action'),
        (
            'event',
            array['meeting_provider_id'],
            'meeting_provider',
            array['meeting_provider_id'],
            'no action'
        ),
        ('event', array['published_by'], '"user"', array['user_id'], 'no action'),
        (
            'event_attendee',
            array['attendance_canceled_by_user_id'],
            '"user"',
            array['user_id'],
            'no action'
        ),
        ('event_attendee', array['event_id'], 'event', array['event_id'], 'no action'),
        ('event_attendee', array['user_id'], '"user"', array['user_id'], 'no action'),
        ('event_category', array['community_id'], 'community', array['community_id'], 'no action'),
        (
            'event_cohost',
            array['event_cohost_status_id'],
            'event_cohost_status',
            array['event_cohost_status_id'],
            'no action'
        ),
        ('event_cohost', array['event_id'], 'event', array['event_id'], 'no action'),
        ('event_cohost', array['group_id'], '"group"', array['group_id'], 'no action'),
        ('event_cohost', array['invited_by'], '"user"', array['user_id'], 'no action'),
        ('event_cohost', array['responded_by'], '"user"', array['user_id'], 'no action'),
        ('event_discount_code', array['event_id'], 'event', array['event_id'], 'cascade'),
        ('event_host', array['event_id'], 'event', array['event_id'], 'no action'),
        ('event_host', array['user_id'], '"user"', array['user_id'], 'no action'),
        (
            'event_invitation_request',
            array['event_id', 'event_ticket_type_id'],
            'event_ticket_type',
            array['event_id', 'event_ticket_type_id'],
            'no action'
        ),
        ('event_invitation_request', array['event_id'], 'event', array['event_id'], 'no action'),
        (
            'event_invitation_request',
            array['event_ticket_type_id'],
            'event_ticket_type',
            array['event_ticket_type_id'],
            'no action'
        ),
        ('event_invitation_request', array['reviewed_by'], '"user"', array['user_id'], 'no action'),
        ('event_invitation_request', array['user_id'], '"user"', array['user_id'], 'no action'),
        ('event_label', array['event_id'], 'event', array['event_id'], 'cascade'),
        ('event_organizer', array['event_id'], 'event', array['event_id'], 'no action'),
        ('event_organizer', array['user_id'], '"user"', array['user_id'], 'no action'),
        (
            'event_purchase',
            array['admission_offer_id', 'event_id', 'user_id'],
            'admission_offer',
            array['admission_offer_id', 'event_id', 'user_id'],
            'no action'
        ),
        (
            'event_purchase',
            array['event_discount_code_id'],
            'event_discount_code',
            array['event_discount_code_id'],
            'no action'
        ),
        (
            'event_purchase',
            array['event_id', 'event_discount_code_id'],
            'event_discount_code',
            array['event_id', 'event_discount_code_id'],
            'no action'
        ),
        (
            'event_purchase',
            array['event_id', 'event_ticket_type_id'],
            'event_ticket_type',
            array['event_id', 'event_ticket_type_id'],
            'no action'
        ),
        ('event_purchase', array['event_id'], 'event', array['event_id'], 'no action'),
        (
            'event_purchase',
            array['event_ticket_type_id'],
            'event_ticket_type',
            array['event_ticket_type_id'],
            'no action'
        ),
        (
            'event_purchase',
            array['external_payment_marked_by_user_id'],
            '"user"',
            array['user_id'],
            'no action'
        ),
        (
            'event_purchase',
            array['payment_provider_id'],
            'payment_provider',
            array['payment_provider_id'],
            'no action'
        ),
        ('event_purchase', array['user_id'], '"user"', array['user_id'], 'no action'),
        (
            'event_purchase_application_fee_adjustment',
            array['event_purchase_id'],
            'event_purchase',
            array['event_purchase_id'],
            'no action'
        ),
        (
            'event_purchase_application_fee_adjustment',
            array['payment_job_id'],
            'payment_job',
            array['payment_job_id'],
            'no action'
        ),
        (
            'event_purchase_credit_note',
            array['event_purchase_refund_id'],
            'event_purchase_refund',
            array['event_purchase_refund_id'],
            'no action'
        ),
        (
            'event_purchase_credit_note',
            array['payment_job_id'],
            'payment_job',
            array['payment_job_id'],
            'no action'
        ),
        (
            'event_purchase_credit_note',
            array['payment_provider_id'],
            'payment_provider',
            array['payment_provider_id'],
            'no action'
        ),
        (
            'event_purchase_refund',
            array['event_purchase_id'],
            'event_purchase',
            array['event_purchase_id'],
            'no action'
        ),
        (
            'event_purchase_refund',
            array['event_refund_request_id'],
            'event_refund_request',
            array['event_refund_request_id'],
            'no action'
        ),
        (
            'event_purchase_refund',
            array['initiated_by_user_id'],
            '"user"',
            array['user_id'],
            'no action'
        ),
        (
            'event_purchase_refund',
            array['payment_job_id'],
            'payment_job',
            array['payment_job_id'],
            'no action'
        ),
        (
            'event_purchase_refund',
            array['payment_provider_id'],
            'payment_provider',
            array['payment_provider_id'],
            'no action'
        ),
        (
            'event_refund_request',
            array['event_purchase_id'],
            'event_purchase',
            array['event_purchase_id'],
            'no action'
        ),
        (
            'event_refund_request',
            array['requested_by_user_id'],
            '"user"',
            array['user_id'],
            'no action'
        ),
        (
            'event_refund_request',
            array['reviewed_by_user_id'],
            '"user"',
            array['user_id'],
            'no action'
        ),
        ('event_series', array['created_by'], '"user"', array['user_id'], 'no action'),
        ('event_series', array['group_id'], '"group"', array['group_id'], 'no action'),
        ('event_speaker', array['event_id'], 'event', array['event_id'], 'no action'),
        ('event_speaker', array['user_id'], '"user"', array['user_id'], 'no action'),
        ('event_sponsor', array['event_id'], 'event', array['event_id'], 'no action'),
        (
            'event_sponsor',
            array['group_sponsor_id'],
            'group_sponsor',
            array['group_sponsor_id'],
            'no action'
        ),
        ('event_survey', array['created_by'], '"user"', array['user_id'], 'set null'),
        ('event_survey', array['event_id'], 'event', array['event_id'], 'cascade'),
        (
            'event_survey_response',
            array['event_survey_id'],
            'event_survey',
            array['event_survey_id'],
            'cascade'
        ),
        ('event_survey_response', array['user_id'], '"user"', array['user_id'], 'cascade'),
        (
            'event_ticket_price_window',
            array['event_ticket_type_id'],
            'event_ticket_type',
            array['event_ticket_type_id'],
            'cascade'
        ),
        ('event_ticket_type', array['event_id'], 'event', array['event_id'], 'cascade'),
        ('event_views', array['event_id'], 'event', array['event_id'], 'set null'),
        ('event_views_utm', array['event_id'], 'event', array['event_id'], 'set null'),
        (
            'event_waitlist',
            array['event_id', 'event_ticket_type_id'],
            'event_ticket_type',
            array['event_id', 'event_ticket_type_id'],
            'no action'
        ),
        ('event_waitlist', array['event_id'], 'event', array['event_id'], 'no action'),
        (
            'event_waitlist',
            array['event_ticket_type_id'],
            'event_ticket_type',
            array['event_ticket_type_id'],
            'no action'
        ),
        ('event_waitlist', array['user_id'], '"user"', array['user_id'], 'no action'),
        ('"group"', array['community_id'], 'community', array['community_id'], 'no action'),
        (
            '"group"',
            array['group_category_id'],
            'group_category',
            array['group_category_id'],
            'no action'
        ),
        (
            '"group"',
            array['group_site_layout_id'],
            'group_site_layout',
            array['group_site_layout_id'],
            'no action'
        ),
        ('"group"', array['parent_group_id'], '"group"', array['group_id'], 'no action'),
        ('"group"', array['region_id'], 'region', array['region_id'], 'no action'),
        ('group_category', array['community_id'], 'community', array['community_id'], 'no action'),
        ('group_member', array['group_id'], '"group"', array['group_id'], 'no action'),
        ('group_member', array['user_id'], '"user"', array['user_id'], 'no action'),
        (
            'group_role_group_permission',
            array['group_permission_id'],
            'group_permission',
            array['group_permission_id'],
            'no action'
        ),
        (
            'group_role_group_permission',
            array['group_role_id'],
            'group_role',
            array['group_role_id'],
            'no action'
        ),
        ('group_sponsor', array['group_id'], '"group"', array['group_id'], 'no action'),
        ('group_team', array['group_id'], '"group"', array['group_id'], 'no action'),
        ('group_team', array['role'], 'group_role', array['group_role_id'], 'no action'),
        ('group_team', array['user_id'], '"user"', array['user_id'], 'no action'),
        ('group_views', array['group_id'], '"group"', array['group_id'], 'set null'),
        ('images', array['created_by'], '"user"', array['user_id'], 'no action'),
        (
            'inbox_conversation',
            array['event_id', 'group_id'],
            'event',
            array['event_id', 'group_id'],
            'set null (event_id)'
        ),
        ('inbox_conversation', array['group_id'], '"group"', array['group_id'], 'no action'),
        (
            'inbox_conversation',
            array['inbox_conversation_status_id'],
            'inbox_conversation_status',
            array['inbox_conversation_status_id'],
            'no action'
        ),
        ('inbox_conversation', array['user_id'], '"user"', array['user_id'], 'set null'),
        ('inbox_message', array['author_user_id'], '"user"', array['user_id'], 'set null'),
        (
            'inbox_message',
            array['inbox_conversation_id'],
            'inbox_conversation',
            array['inbox_conversation_id'],
            'no action'
        ),
        ('legacy_event_host', array['event_id'], 'event', array['event_id'], 'no action'),
        ('legacy_event_speaker', array['event_id'], 'event', array['event_id'], 'no action'),
        (
            'meeting',
            array['auto_end_check_outcome'],
            'meeting_auto_end_check_outcome',
            array['meeting_auto_end_check_outcome_id'],
            'no action'
        ),
        ('meeting', array['event_id'], 'event', array['event_id'], 'set null'),
        (
            'meeting',
            array['meeting_provider_id'],
            'meeting_provider',
            array['meeting_provider_id'],
            'no action'
        ),
        ('meeting', array['session_id'], 'session', array['session_id'], 'set null'),
        ('notification', array['kind'], 'notification_kind', array['name'], 'restrict'),
        (
            'notification',
            array['notification_template_data_id'],
            'notification_template_data',
            array['notification_template_data_id'],
            'no action'
        ),
        ('notification', array['user_id'], '"user"', array['user_id'], 'cascade'),
        (
            'notification_attachment',
            array['attachment_id'],
            'attachment',
            array['attachment_id'],
            'restrict'
        ),
        (
            'notification_attachment',
            array['notification_id'],
            'notification',
            array['notification_id'],
            'cascade'
        ),
        (
            'notification_kind',
            array['notification_category_id'],
            'notification_category',
            array['notification_category_id'],
            'no action'
        ),
        (
            'payment_job',
            array['event_purchase_id'],
            'event_purchase',
            array['event_purchase_id'],
            'no action'
        ),
        (
            'payment_job',
            array['payment_provider_id'],
            'payment_provider',
            array['payment_provider_id'],
            'no action'
        ),
        (
            'payment_job',
            array['recovery_completed_by_user_id'],
            '"user"',
            array['user_id'],
            'no action'
        ),
        (
            'payment_provider_tax_location',
            array['payment_provider_id'],
            'payment_provider',
            array['payment_provider_id'],
            'no action'
        ),
        (
            'payment_provider_tax_product',
            array['payment_provider_id'],
            'payment_provider',
            array['payment_provider_id'],
            'no action'
        ),
        ('region', array['community_id'], 'community', array['community_id'], 'no action'),
        (
            'session',
            array['cfs_submission_id'],
            'cfs_submission',
            array['cfs_submission_id'],
            'no action'
        ),
        ('session', array['event_id'], 'event', array['event_id'], 'cascade'),
        (
            'session',
            array['meeting_provider_id'],
            'meeting_provider',
            array['meeting_provider_id'],
            'no action'
        ),
        ('session', array['session_kind_id'], 'session_kind', array['session_kind_id'], 'no action'),
        (
            'session_label',
            array['event_label_id'],
            'event_label',
            array['event_label_id'],
            'cascade'
        ),
        ('session_label', array['session_id'], 'session', array['session_id'], 'cascade'),
        ('session_proposal', array['co_speaker_user_id'], '"user"', array['user_id'], 'no action'),
        (
            'session_proposal',
            array['session_proposal_level_id'],
            'session_proposal_level',
            array['session_proposal_level_id'],
            'no action'
        ),
        (
            'session_proposal',
            array['session_proposal_status_id'],
            'session_proposal_status',
            array['session_proposal_status_id'],
            'no action'
        ),
        ('session_proposal', array['user_id'], '"user"', array['user_id'], 'no action'),
        ('session_speaker', array['session_id'], 'session', array['session_id'], 'cascade'),
        ('session_speaker', array['user_id'], '"user"', array['user_id'], 'no action'),
        (
            'user_badge',
            array['badge_id', 'group_id'],
            'badge',
            array['badge_id', 'group_id'],
            'set null (badge_id)'
        ),
        (
            'user_badge',
            array['badge_status_list_id', 'group_id'],
            'badge_status_list',
            array['badge_status_list_id', 'group_id'],
            'no action'
        ),
        (
            'user_badge',
            array['event_id', 'group_id'],
            'event',
            array['event_id', 'group_id'],
            'set null (event_id)'
        ),
        ('user_badge', array['group_id'], '"group"', array['group_id'], 'no action'),
        ('user_badge', array['revoked_by_user_id'], '"user"', array['user_id'], 'set null'),
        ('user_badge', array['user_id'], '"user"', array['user_id'], 'set null'),
        ('user_group_notification_mute', array['group_id'], '"group"', array['group_id'], 'cascade'),
        ('user_group_notification_mute', array['user_id'], '"user"', array['user_id'], 'cascade'),
        (
            'user_notification_opt_out',
            array['notification_category_id'],
            'notification_category',
            array['notification_category_id'],
            'no action'
        ),
        ('user_notification_opt_out', array['user_id'], '"user"', array['user_id'], 'cascade')
    $$,
    'Foreign keys should match expected columns, referenced keys and delete actions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
