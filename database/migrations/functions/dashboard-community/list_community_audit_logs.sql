-- Returns paginated audit log rows for the community dashboard.
create or replace function list_community_audit_logs(p_community_id uuid, p_filters jsonb)
returns json as $$
    select search_audit_logs(
        p_community_id,
        null,
        null,
        array[
            'community_custom_notification_sent',
            'community_team_invitation_accepted',
            'community_team_invitation_rejected',
            'community_team_member_added',
            'community_team_member_removed',
            'community_team_member_role_updated',
            'community_updated',
            'event_category_added',
            'event_category_deleted',
            'event_category_updated',
            'group_activated',
            'group_added',
            'group_category_added',
            'group_category_deleted',
            'group_category_updated',
            'group_deactivated',
            'group_deleted',
            'group_external_payments_updated',
            'group_payment_recipient_updated',
            'group_updated',
            'region_added',
            'region_deleted',
            'region_updated'
        ]::text[],
        p_filters
    );
$$ language sql stable;
