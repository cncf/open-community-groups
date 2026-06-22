-- Deletes a user from regular group membership.
create or replace function delete_group_member(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_user_id uuid
) returns void as $$
begin
    delete from group_member
    where group_id = p_group_id
      and user_id = p_user_id;

    if not found then
        raise exception 'user is not a group member';
    end if;

    perform insert_audit_log(
        'group_member_removed',
        p_actor_user_id,
        'user',
        p_user_id,
        (select alliance_id from "group" where group_id = p_group_id),
        p_group_id
    );
end;
$$ language plpgsql;
