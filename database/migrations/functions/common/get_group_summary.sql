-- Returns summary information about a group.
create or replace function get_group_summary(
    p_community_id uuid,
    p_group_id uuid
)
returns json as $$
    -- Build group summary payload
    select json_strip_nulls(json_build_object(
        -- Include core summary fields
        'active', g.active,
        'category', group_category_json(gc),
        'community_display_name', c.display_name,
        'community_name', c.name,
        'created_at', epoch_seconds(g.created_at),
        'group_id', g.group_id,
        'name', g.name,
        'slug', g.slug,

        -- Include optional group profile fields
        'banner_dark_url', g.banner_dark_url,
        'banner_mobile_dark_url', g.banner_mobile_dark_url,
        'banner_mobile_url', g.banner_mobile_url,
        'banner_url', g.banner_url,
        'city', g.city,
        'country_code', g.country_code,
        'country_name', g.country_name,
        'description_short', g.description_short,
        'latitude', st_y(g.location::geometry),
        -- Pair the dark logo with the level that provides the light logo
        'logo_dark_url', paired_dark_image_url(
            g.logo_url, g.logo_dark_url,
            c.logo_url, c.logo_dark_url
        ),
        'logo_url', coalesce(g.logo_url, c.logo_url),
        'longitude', st_x(g.location::geometry),
        'og_image_url', g.og_image_url,
        'region', group_region_json(r),
        'slug_pretty', g.slug_pretty,
        'state', g.state
    )) as json_data
    from "group" g
    join community c using (community_id)
    join group_category gc using (group_category_id)
    left join region r using (region_id)
    where g.group_id = p_group_id
    and g.community_id = p_community_id;
$$ language sql stable;
