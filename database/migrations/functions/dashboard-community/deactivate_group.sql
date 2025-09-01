-- deactivate_group sets active=false without marking as deleted.
create or replace function deactivate_group(
    p_community_id uuid,
    p_group_id uuid
)
returns void as $$
begin
    update "group" set
        active = false
    where group_id = p_group_id
    and community_id = p_community_id
    and deleted = false;

    if not found then
        raise exception 'group not found';
    end if;
end;
$$ language plpgsql;