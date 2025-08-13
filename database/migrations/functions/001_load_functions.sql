{{ template "common/format_group_description.sql" }}
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

{{ template "dashboard-common/update_group.sql" }}

{{ template "dashboard-community/add_group.sql" }}
{{ template "dashboard-community/delete_group.sql" }}
{{ template "dashboard-community/list_community_groups.sql" }}
{{ template "dashboard-community/list_group_categories.sql" }}
{{ template "dashboard-community/list_regions.sql" }}
{{ template "dashboard-community/update_community.sql" }}

{{ template "dashboard-group/add_event.sql" }}
{{ template "dashboard-group/delete_event.sql" }}
{{ template "dashboard-group/list_event_categories.sql" }}
{{ template "dashboard-group/list_event_kinds.sql" }}
{{ template "dashboard-group/list_group_events.sql" }}
{{ template "dashboard-group/update_event.sql" }}

{{ template "event/get_event.sql" }}

{{ template "group/get_group.sql" }}
{{ template "group/get_group_past_events.sql" }}
{{ template "group/get_group_upcoming_events.sql" }}

---- create above / drop below ----

-- Nothing to do
