-- Adds reusable badge artwork to a group gallery.
create or replace function add_badge_artwork(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid,
    p_file_name text
)
returns void as $$
declare
    v_badge_artwork_id uuid;
    v_file_name text;
begin
    -- Authorize the actor against the requested community and group
    if not user_has_group_permission(
        p_community_id,
        p_group_id,
        p_actor_user_id,
        'group.badges.write'
    ) then
        raise exception 'badge permission denied' using errcode = 'insufficient_privilege';
    end if;

    -- Normalize the content-addressed file name stored by the image service
    v_file_name := nullif(
        btrim(regexp_replace(p_file_name, '^/images/(badges/)?', '')),
        ''
    );

    -- Add the gallery entry without duplicating an existing image
    insert into badge_artwork (file_name, group_id)
    values (v_file_name, p_group_id)
    on conflict (group_id, file_name) do nothing
    returning badge_artwork_id into v_badge_artwork_id;

    if v_badge_artwork_id is null then
        return;
    end if;

    -- Record the successful gallery mutation
    perform insert_audit_log(
        'badge_artwork_added',
        p_actor_user_id,
        'badge_artwork',
        v_badge_artwork_id,
        p_community_id,
        p_group_id,
        null,
        jsonb_build_object('file_name', v_file_name)
    );

exception
    when not_null_violation or check_violation then
        raise exception 'badge artwork file name is invalid';
end;
$$ language plpgsql;
