-- activate_group sets active=true for an existing, non-deleted group.
create or replace function activate_group(
    p_community_id uuid,
    p_group_id uuid
)
returns void as $$
begin
    -- Activate the target group
    update "group" set
        active = true
    where group_id = p_group_id
    and community_id = p_community_id
    and deleted = false;

    -- Ensure the target group exists and is active
    if not found then
        raise exception 'group not found or inactive';
    end if;
end;
$$ language plpgsql;
