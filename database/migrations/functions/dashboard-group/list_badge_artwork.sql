-- Lists reusable artwork in a group badge gallery.
create or replace function list_badge_artwork(p_group_id uuid)
returns json as $$
    select coalesce(
        json_agg(
            json_build_object(
                'badge_artwork_id', ba.badge_artwork_id,
                'file_name', ba.file_name
            )
            order by ba.created_at desc, ba.badge_artwork_id desc
        ),
        '[]'::json
    )
    from badge_artwork ba
    where ba.group_id = p_group_id;
$$ language sql;
