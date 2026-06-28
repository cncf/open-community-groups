-- Approves a pending join request and adds the user as a group member.
create or replace function approve_group_join_request(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_user_id uuid
) returns void as $$
begin
    update group_join_request
    set status = 'approved',
        reviewed_at = current_timestamp,
        reviewed_by = p_actor_user_id
    where group_id = p_group_id
    and user_id = p_user_id
    and status = 'pending';

    if not found then
        raise exception 'pending group join request not found';
    end if;

    insert into group_member (group_id, user_id)
    values (p_group_id, p_user_id)
    on conflict (group_id, user_id) do nothing;

    perform insert_audit_log(
        'group_join_request_approved',
        p_actor_user_id,
        'user',
        p_user_id,
        (select alliance_id from "group" where group_id = p_group_id),
        p_group_id
    );
end;
$$ language plpgsql;
