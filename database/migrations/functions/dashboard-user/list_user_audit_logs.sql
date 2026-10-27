-- Returns paginated audit log rows for the user dashboard.
-- The user dashboard has no actor filter, so it is removed from the filters.
create or replace function list_user_audit_logs(p_actor_user_id uuid, p_filters jsonb)
returns json as $$
    select search_audit_logs(
        null,
        null,
        p_actor_user_id,
        array[
            'community_team_invitation_accepted',
            'community_team_invitation_rejected',
            'event_admission_offer_declined',
            'event_attendee_invitation_accepted',
            'event_attendee_invitation_rejected',
            'group_notifications_muted',
            'group_notifications_unmuted',
            'group_team_invitation_accepted',
            'group_team_invitation_rejected',
            'inbox_conversation_started',
            'inbox_message_sent',
            'session_proposal_added',
            'session_proposal_co_speaker_invitation_accepted',
            'session_proposal_co_speaker_invitation_rejected',
            'session_proposal_deleted',
            'session_proposal_updated',
            'submission_resubmitted',
            'submission_withdrawn',
            'user_details_updated',
            'user_notification_preferences_updated',
            'user_password_updated'
        ]::text[],
        p_filters - 'actor'
    );
$$ language sql stable;
