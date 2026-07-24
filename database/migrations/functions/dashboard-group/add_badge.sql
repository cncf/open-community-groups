-- Adds a badge definition to a group.
create or replace function add_badge(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid,
    p_badge jsonb
)
returns void as $$
declare
    v_badge_id uuid;
    v_badge_name text;
    v_image_file_name text;
begin
    -- Authorize the actor against the requested community and group
    if not user_has_group_permission(
        p_community_id,
        p_group_id,
        p_actor_user_id,
        'group.events.write'
    ) then
        raise exception 'badge permission denied' using errcode = 'insufficient_privilege';
    end if;

    -- Normalize and lock the selected gallery artwork
    v_image_file_name := regexp_replace(p_badge->>'image_file_name', '^/images/(badges/)?', '');
    perform 1
    from badge_artwork
    where file_name = v_image_file_name
    and group_id = p_group_id
    for key share;

    if not found then
        raise exception 'badge artwork not found';
    end if;

    -- Insert the definition from validated group-owned data
    insert into badge (
        criteria,
        description,
        group_id,
        image_file_name,
        name
    ) values (
        nullif(btrim(p_badge->>'criteria'), ''),
        nullif(btrim(p_badge->>'description'), ''),
        p_group_id,
        v_image_file_name,
        nullif(btrim(p_badge->>'name'), '')
    )
    returning badge_id, name into v_badge_id, v_badge_name;

    -- Record the successful definition creation
    perform insert_audit_log(
        'badge_added',
        p_actor_user_id,
        'badge',
        v_badge_id,
        p_community_id,
        p_group_id,
        null,
        jsonb_build_object('badge_name', v_badge_name)
    );

exception
    when not_null_violation or check_violation then
        raise exception 'badge fields are invalid';
end;
$$ language plpgsql;
