-- Returns the bounding box envelope of the search filters provided, or null
-- unless all four bbox keys are present.
create or replace function search_bbox_envelope(p_filters jsonb)
returns geometry as $$
    select case
        when p_filters ?& array['bbox_ne_lat', 'bbox_ne_lon', 'bbox_sw_lat', 'bbox_sw_lon'] then
            st_makeenvelope(
                (p_filters->>'bbox_sw_lon')::real,
                (p_filters->>'bbox_sw_lat')::real,
                (p_filters->>'bbox_ne_lon')::real,
                (p_filters->>'bbox_ne_lat')::real,
                4326
            )
    end;
$$ language sql immutable;
