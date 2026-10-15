-- get_group_utm_settings returns the UTM campaigns, extra mediums, and sources
-- accepted for the event page views of a group.
create or replace function get_group_utm_settings(
    p_community_id uuid,
    p_group_id uuid
)
returns json as $$
    select json_build_object(
        'campaigns', g.utm_campaigns,
        'mediums', g.utm_mediums,
        'sources', g.utm_sources
    )
    from "group" g
    where g.group_id = p_group_id
    and g.community_id = p_community_id
    and g.deleted = false;
$$ language sql;
