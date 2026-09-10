-- Deletes a group badge definition while preserving issued credentials.
create or replace function delete_badge(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid,
    p_badge_id uuid
)
returns void as $$
declare
    v_badge_name text;
begin
    -- Delete only a definition owned by the requested group
    delete from badge
    where badge_id = p_badge_id
    and group_id = p_group_id
    returning name into v_badge_name;

    if not found then
        raise exception 'badge not found' using errcode = 'OCG01';
    end if;

    -- Record the successful definition deletion
    perform insert_audit_log(
        'badge_deleted',
        p_actor_user_id,
        'badge',
        p_badge_id,
        p_community_id,
        p_group_id,
        null,
        jsonb_build_object('badge_name', v_badge_name)
    );
end;
$$ language plpgsql;
