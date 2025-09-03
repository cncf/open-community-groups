{{ template "auth/get_user_by_id.sql" }}
{{ template "auth/sign_up_user.sql" }}
{{ template "auth/update_user_details.sql" }}
{{ template "auth/user_owns_community.sql" }}
{{ template "auth/user_owns_group.sql" }}
{{ template "auth/verify_email.sql" }}

{{ template "common/get_group_summary.sql" }}
{{ template "common/get_event_detailed.sql" }}
{{ template "common/get_event_full.sql" }}
{{ template "common/get_event_summary.sql" }}
{{ template "common/get_group_detailed.sql" }}
{{ template "common/get_group_full.sql" }}

{{ template "community/get_community.sql" }}
{{ template "community/get_community_filters_options.sql" }}
{{ template "community/get_community_home_stats.sql" }}
{{ template "community/get_community_recently_added_groups.sql" }}
{{ template "community/get_community_upcoming_events.sql" }}
{{ template "community/search_community_events.sql" }}
{{ template "community/search_community_groups.sql" }}

{{ template "dashboard-common/search_user.sql" }}
{{ template "dashboard-common/update_group.sql" }}

{{ template "dashboard-community/add_community_team_member.sql" }}
{{ template "dashboard-community/add_group.sql" }}
{{ template "dashboard-community/deactivate_group.sql" }}
{{ template "dashboard-community/delete_community_team_member.sql" }}
{{ template "dashboard-community/delete_group.sql" }}
{{ template "dashboard-community/list_community_groups.sql" }}
{{ template "dashboard-community/list_community_team_members.sql" }}
{{ template "dashboard-community/list_group_categories.sql" }}
{{ template "dashboard-community/list_regions.sql" }}
{{ template "dashboard-community/update_community.sql" }}

{{ template "dashboard-group/add_event.sql" }}
{{ template "dashboard-group/delete_event.sql" }}
{{ template "dashboard-group/list_event_categories.sql" }}
{{ template "dashboard-group/list_event_kinds.sql" }}
{{ template "dashboard-group/list_group_events.sql" }}
{{ template "dashboard-group/list_user_groups.sql" }}
{{ template "dashboard-group/update_event.sql" }}

{{ template "event/attend_event.sql" }}
{{ template "event/get_event.sql" }}
{{ template "event/is_event_attendee.sql" }}
{{ template "event/leave_event.sql" }}

{{ template "group/get_group.sql" }}
{{ template "group/get_group_past_events.sql" }}
{{ template "group/get_group_upcoming_events.sql" }}
{{ template "group/is_group_member.sql" }}
{{ template "group/join_group.sql" }}
{{ template "group/leave_group.sql" }}

---- create above / drop below ----

drop function if exists remove_community_team_member(uuid, uuid);
drop function if exists list_community_team(uuid);
