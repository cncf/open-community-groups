-- Deletes a sponsor from the group.
create or replace function delete_group_sponsor(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_group_sponsor_id uuid
)
returns void as $$
begin
    -- Check if the sponsor is used by any events
    if exists (
        select 1
        from event_sponsor
        where group_sponsor_id = p_group_sponsor_id
    ) then
        raise exception 'sponsor is used by one or more events';
    end if;

    -- Delete the sponsor
    delete from group_sponsor
    where group_sponsor_id = p_group_sponsor_id
    and group_id = p_group_id;

    if found then
        -- Track the deleted sponsor
        perform insert_audit_log(
            'group_sponsor_deleted',
            p_actor_user_id,
            'group_sponsor',
            p_group_sponsor_id,
            (select community_id from "group" where group_id = p_group_id),
            p_group_id
        );
    end if;
end;
$$ language plpgsql;
