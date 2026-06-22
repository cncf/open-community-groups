-- Returns whether an image URL is configured for a public Open Graph preview.
create or replace function is_open_graph_image(p_image_url text)
returns boolean as $$
    select exists (
        select 1
        from alliance
        where og_image_url = p_image_url
        and active = true
    )
    or exists (
        select 1
        from "group" g
        join alliance c using (alliance_id)
        where g.og_image_url = p_image_url
        and g.active = true
        and g.deleted = false
        and c.active = true
    );
$$ language sql;
