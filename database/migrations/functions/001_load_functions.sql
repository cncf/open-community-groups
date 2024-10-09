{{ template "community/get_community.sql" }}
{{ template "community/get_community_recently_added_groups.sql" }}
{{ template "community/get_community_upcoming_in_person_events.sql" }}
{{ template "community/get_community_upcoming_virtual_events.sql" }}
{{ template "community/search_community_events.sql" }}
{{ template "community/search_community_groups.sql" }}

---- create above / drop below ----

-- Nothing to do
