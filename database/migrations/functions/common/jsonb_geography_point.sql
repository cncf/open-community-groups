-- Converts JSONB latitude and longitude fields into a geography point.
create or replace function jsonb_geography_point(p_value jsonb)
returns geography as $$
    select case
        when p_value is null
          or jsonb_typeof(p_value) = 'null'
          or p_value->>'latitude' is null
          or p_value->>'longitude' is null then null
        else ST_SetSRID(
            ST_MakePoint(
                (p_value->>'longitude')::float,
                (p_value->>'latitude')::float
            ),
            4326
        )::geography
    end;
$$ language sql immutable;
