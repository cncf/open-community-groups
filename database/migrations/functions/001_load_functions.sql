{{ template "auth/get_user_by_id.sql" }} -- Do not sort alphabetically, has dependency
{{ template "auth/get_user_by_email.sql" }}
{{ template "auth/get_user_by_id_verified.sql" }}
{{ template "auth/get_user_by_username.sql" }}
{{ template "auth/sign_up_user.sql" }}
{{ template "auth/update_user_details.sql" }}
{{ template "auth/update_user_password.sql" }}
{{ template "auth/user_owns_community.sql" }}
{{ template "auth/user_owns_group.sql" }}
{{ template "auth/user_owns_groups_in_community.sql" }}
{{ template "auth/verify_email.sql" }}

{{ template "common/generate_slug.sql" }}
{{ template "common/get_community_full.sql" }}
{{ template "common/get_community_summary.sql" }} -- Do not sort alphabetically, has dependency
{{ template "common/get_group_summary.sql" }} -- Do not sort alphabetically, has dependency
{{ template "common/get_event_full.sql" }}
{{ template "common/get_event_summary.sql" }}
{{ template "common/get_group_full.sql" }}
{{ template "common/search_events.sql" }}
{{ template "common/search_groups.sql" }}
{{ template "community/get_community_id_by_name.sql" }}
{{ template "community/get_community_name_by_id.sql" }}
{{ template "community/get_community_recently_added_groups.sql" }}
{{ template "community/get_community_site_stats.sql" }}
{{ template "community/get_community_upcoming_events.sql" }}

{{ template "dashboard-common/search_user.sql" }}
{{ template "dashboard-common/update_group.sql" }}

{{ template "dashboard-community/activate_group.sql" }}
{{ template "dashboard-community/add_community_team_member.sql" }}
{{ template "dashboard-community/add_group.sql" }}
{{ template "dashboard-community/deactivate_group.sql" }}
{{ template "dashboard-community/delete_community_team_member.sql" }}
{{ template "dashboard-community/delete_group.sql" }}
{{ template "dashboard-community/get_community_stats.sql" }}
{{ template "dashboard-community/list_community_team_members.sql" }}
{{ template "dashboard-community/list_group_categories.sql" }}
{{ template "dashboard-community/list_regions.sql" }}
{{ template "dashboard-community/list_user_communities.sql" }}
{{ template "dashboard-community/update_community.sql" }}

{{ template "dashboard-group/add_event.sql" }}
{{ template "dashboard-group/add_group_sponsor.sql" }}
{{ template "dashboard-group/add_group_team_member.sql" }}
{{ template "dashboard-group/cancel_event.sql" }}
{{ template "dashboard-group/delete_event.sql" }}
{{ template "dashboard-group/delete_group_sponsor.sql" }}
{{ template "dashboard-group/delete_group_team_member.sql" }}
{{ template "dashboard-group/get_cfs_submission_notification_data.sql" }}
{{ template "dashboard-group/get_group_sponsor.sql" }}
{{ template "dashboard-group/get_group_stats.sql" }}
{{ template "dashboard-group/is_event_meeting_in_sync.sql" }}
{{ template "dashboard-group/is_session_meeting_in_sync.sql" }}
{{ template "dashboard-group/list_cfs_submission_statuses_for_review.sql" }}
{{ template "dashboard-group/list_event_approved_cfs_submissions.sql" }}
{{ template "dashboard-group/list_event_attendees_ids.sql" }}
{{ template "dashboard-group/list_event_categories.sql" }}
{{ template "dashboard-group/list_event_cfs_submissions.sql" }}
{{ template "dashboard-group/list_event_kinds.sql" }}
{{ template "dashboard-group/list_group_events.sql" }}
{{ template "dashboard-group/list_group_members.sql" }}
{{ template "dashboard-group/list_group_members_ids.sql" }}
{{ template "dashboard-group/list_group_roles.sql" }}
{{ template "dashboard-group/list_group_sponsors.sql" }}
{{ template "dashboard-group/list_group_team_members.sql" }}
{{ template "dashboard-group/list_group_team_members_ids.sql" }}
{{ template "dashboard-group/list_session_kinds.sql" }}
{{ template "dashboard-group/list_user_groups.sql" }}
{{ template "dashboard-group/publish_event.sql" }}
{{ template "dashboard-group/search_event_attendees.sql" }}
{{ template "dashboard-group/unpublish_event.sql" }}
{{ template "dashboard-group/update_cfs_submission.sql" }}
{{ template "dashboard-group/update_group_sponsor.sql" }}
{{ template "dashboard-group/update_group_team_member_role.sql" }}
{{ template "dashboard-group/update_event.sql" }}

{{ template "dashboard-user/accept_community_team_invitation.sql" }}
{{ template "dashboard-user/accept_group_team_invitation.sql" }}
{{ template "dashboard-user/add_session_proposal.sql" }}
{{ template "dashboard-user/delete_session_proposal.sql" }}
{{ template "dashboard-user/list_session_proposal_levels.sql" }}
{{ template "dashboard-user/list_user_cfs_submissions.sql" }}
{{ template "dashboard-user/list_user_community_team_invitations.sql" }}
{{ template "dashboard-user/list_user_group_team_invitations.sql" }}
{{ template "dashboard-user/list_user_session_proposals.sql" }}
{{ template "dashboard-user/resubmit_cfs_submission.sql" }}
{{ template "dashboard-user/update_session_proposal.sql" }}
{{ template "dashboard-user/withdraw_cfs_submission.sql" }}

{{ template "event/add_cfs_submission.sql" }}
{{ template "event/attend_event.sql" }}
{{ template "event/check_in_event.sql" }}
{{ template "event/get_event_full_by_slug.sql" }}
{{ template "event/get_event_summary_by_id.sql" }}
{{ template "event/is_event_attendee.sql" }}
{{ template "event/is_event_check_in_window_open.sql" }}
{{ template "event/leave_event.sql" }}
{{ template "event/list_user_session_proposals_for_cfs_event.sql" }}

{{ template "group/get_group_full_by_slug.sql" }}
{{ template "group/get_group_past_events.sql" }}
{{ template "group/get_group_upcoming_events.sql" }}
{{ template "group/is_group_member.sql" }}
{{ template "group/join_group.sql" }}
{{ template "group/leave_group.sql" }}

{{ template "meetings/add_meeting.sql" }}
{{ template "meetings/delete_meeting.sql" }}
{{ template "meetings/get_meeting_out_of_sync.sql" }}
{{ template "meetings/set_meeting_error.sql" }}
{{ template "meetings/update_meeting.sql" }}
{{ template "meetings/update_meeting_recording_url.sql" }}

{{ template "notifications/enqueue_notification.sql" }}
{{ template "notifications/get_pending_notification.sql" }}

{{ template "site/get_filters_options.sql" }}
{{ template "site/get_site_home_stats.sql" }}
{{ template "site/get_site_recently_added_groups.sql" }}
{{ template "site/get_site_settings.sql" }}
{{ template "site/get_site_stats.sql" }}
{{ template "site/get_site_upcoming_events.sql" }}
{{ template "site/list_communities.sql" }}

---- create above / drop below ----

-- Nothing to do
