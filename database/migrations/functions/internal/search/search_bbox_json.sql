-- Returns the corners of the extent provided as search bbox JSON, or null when
-- there is no extent.
create or replace function search_bbox_json(p_extent geometry)
returns json as $$
    select case
        when p_extent is not null then
            json_build_object(
                'ne_lat', st_ymax(p_extent),
                'ne_lon', st_xmax(p_extent),
                'sw_lat', st_ymin(p_extent),
                'sw_lon', st_xmin(p_extent)
            )
    end;
$$ language sql immutable;
