{{ template "auth/get_user_by_id.sql" }}
{{ template "auth/sign_up_user.sql" }}
{{ template "auth/update_user_details.sql" }}
{{ template "auth/user_owns_community.sql" }}
{{ template "auth/user_owns_group.sql" }}
{{ template "auth/verify_email.sql" }}

{{ template "common/generate_slug.sql" }}
{{ template "common/get_group_summary.sql" }} -- Do not sort alphabetically, has dependency
{{ template "common/get_event_full.sql" }}
{{ template "common/get_event_summary.sql" }}
{{ template "common/get_group_full.sql" }}
{{ template "common/search_community_events.sql" }}
{{ template "common/search_community_groups.sql" }}

{{ template "community/get_community.sql" }}
{{ template "community/get_community_filters_options.sql" }}
{{ template "community/get_community_home_stats.sql" }}
{{ template "community/get_community_recently_added_groups.sql" }}
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
{{ template "dashboard-community/update_community.sql" }}

{{ template "dashboard-group/add_event.sql" }}
{{ template "dashboard-group/add_group_sponsor.sql" }}
{{ template "dashboard-group/add_group_team_member.sql" }}
{{ template "dashboard-group/cancel_event.sql" }}
{{ template "dashboard-group/delete_event.sql" }}
{{ template "dashboard-group/delete_group_sponsor.sql" }}
{{ template "dashboard-group/delete_group_team_member.sql" }}
{{ template "dashboard-group/get_group_sponsor.sql" }}
{{ template "dashboard-group/get_group_stats.sql" }}
{{ template "dashboard-group/is_event_meeting_in_sync.sql" }}
{{ template "dashboard-group/is_session_meeting_in_sync.sql" }}
{{ template "dashboard-group/list_event_attendees_ids.sql" }}
{{ template "dashboard-group/list_event_categories.sql" }}
{{ template "dashboard-group/list_event_kinds.sql" }}
{{ template "dashboard-group/list_group_events.sql" }}
{{ template "dashboard-group/list_group_members.sql" }}
{{ template "dashboard-group/list_group_members_ids.sql" }}
{{ template "dashboard-group/list_group_roles.sql" }}
{{ template "dashboard-group/list_group_sponsors.sql" }}
{{ template "dashboard-group/list_group_team_members.sql" }}
{{ template "dashboard-group/list_session_kinds.sql" }}
{{ template "dashboard-group/list_user_groups.sql" }}
{{ template "dashboard-group/publish_event.sql" }}
{{ template "dashboard-group/search_event_attendees.sql" }}
{{ template "dashboard-group/unpublish_event.sql" }}
{{ template "dashboard-group/update_group_sponsor.sql" }}
{{ template "dashboard-group/update_group_team_member_role.sql" }}
{{ template "dashboard-group/update_event.sql" }}

{{ template "dashboard-user/accept_community_team_invitation.sql" }}
{{ template "dashboard-user/accept_group_team_invitation.sql" }}
{{ template "dashboard-user/list_user_community_team_invitations.sql" }}
{{ template "dashboard-user/list_user_group_team_invitations.sql" }}

{{ template "event/attend_event.sql" }}
{{ template "event/check_in_event.sql" }}
{{ template "event/get_event_full_by_slug.sql" }}
{{ template "event/get_event_summary_by_id.sql" }}
{{ template "event/is_event_attendee.sql" }}
{{ template "event/is_event_check_in_window_open.sql" }}
{{ template "event/leave_event.sql" }}

{{ template "group/get_group_full_by_slug.sql" }}
{{ template "group/get_group_past_events.sql" }}
{{ template "group/get_group_upcoming_events.sql" }}
{{ template "group/is_group_member.sql" }}
{{ template "group/join_group.sql" }}
{{ template "group/leave_group.sql" }}

{{ template "meetings/add_meeting.sql" }}
{{ template "meetings/delete_meeting.sql" }}
{{ template "meetings/get_meeting_out_of_sync.sql" }}
{{ template "meetings/update_meeting.sql" }}
{{ template "meetings/update_meeting_recording_url.sql" }}

{{ template "notifications/get_pending_notification.sql" }}

---- create above / drop below ----

-- Nothing to do
