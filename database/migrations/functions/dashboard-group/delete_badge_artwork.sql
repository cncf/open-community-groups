-- Removes unreferenced artwork from a group badge gallery.
create or replace function delete_badge_artwork(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid,
    p_badge_artwork_id uuid
)
returns void as $$
declare
    v_file_name text;
begin
    -- Lock the group-owned gallery entry before checking its references
    select file_name
    into v_file_name
    from badge_artwork
    where badge_artwork_id = p_badge_artwork_id
    and group_id = p_group_id
    for update;

    if not found then
        raise exception 'badge artwork not found' using errcode = 'OCG01';
    end if;
    if exists (
        select 1
        from badge
        where group_id = p_group_id
        and image_file_name = v_file_name
    ) then
        raise exception 'badge artwork is used by a badge' using errcode = 'OCG01';
    end if;

    -- Remove only the gallery reference, leaving stored image data intact
    delete from badge_artwork
    where badge_artwork_id = p_badge_artwork_id;

    -- Record the successful gallery removal
    perform insert_audit_log(
        'badge_artwork_deleted',
        p_actor_user_id,
        'badge_artwork',
        p_badge_artwork_id,
        p_community_id,
        p_group_id,
        null,
        jsonb_build_object('file_name', v_file_name)
    );
end;
$$ language plpgsql;
