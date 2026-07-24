-- Updates a group badge definition without changing issued snapshots.
create or replace function update_badge(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid,
    p_badge_id uuid,
    p_badge jsonb
)
returns void as $$
declare
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

    -- Normalize and lock the selected group-owned gallery artwork
    v_image_file_name := regexp_replace(p_badge->>'image_file_name', '^/images/(badges/)?', '');
    perform 1
    from badge_artwork
    where file_name = v_image_file_name
    and group_id = p_group_id
    for key share;

    if not found then
        raise exception 'badge artwork not found';
    end if;

    -- Update only the current definition, preserving issued snapshots
    update badge
    set
        criteria = nullif(btrim(p_badge->>'criteria'), ''),
        description = nullif(btrim(p_badge->>'description'), ''),
        image_file_name = v_image_file_name,
        name = nullif(btrim(p_badge->>'name'), '')
    where badge_id = p_badge_id
    and group_id = p_group_id
    returning name into v_badge_name;

    if not found then
        raise exception 'badge not found';
    end if;

    -- Record the successful definition update
    perform insert_audit_log(
        'badge_updated',
        p_actor_user_id,
        'badge',
        p_badge_id,
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
