-- Returns the group team seats in a community that match the contact filters.
-- A seat matches only when it passes every filter on its own; an empty or
-- missing filter list matches every value. Callers validate the filters with
-- validate_community_contact_filters first.
create or replace function community_contact_team_seats(
    p_community_id uuid,
    p_filters jsonb
)
returns table (group_id uuid, user_id uuid) as $$
    -- Select accepted and verified seats of available groups matching every filter
    select
        gt.group_id,
        gt.user_id
    from community_contact_filter_values(p_filters) f
    cross join "group" g
    join group_team gt on gt.group_id = g.group_id
    join "user" u on u.user_id = gt.user_id
    where g.community_id = p_community_id
    and g.active = true
    and g.deleted = false
    and gt.accepted = true
    and u.email_verified = true
    and (
        cardinality(f.group_category_ids) = 0
        or g.group_category_id = any(f.group_category_ids)
    )
    and (
        (cardinality(f.region_ids) = 0 and not f.include_no_region)
        or g.region_id = any(f.region_ids)
        or (f.include_no_region and g.region_id is null)
    )
    and (
        cardinality(f.roles) = 0
        or gt.role = any(f.roles)
    );
$$ language sql stable;
