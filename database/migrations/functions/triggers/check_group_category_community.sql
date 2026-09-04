-- Rejects groups whose category belongs to another community.
create or replace function check_group_category_community()
returns trigger as $$
declare
    v_category_community_id uuid;
begin
    -- Resolve the community that owns the group category
    select community_id into v_category_community_id
    from group_category
    where group_category_id = new.group_category_id;

    -- Reject categories from another community
    if v_category_community_id is distinct from new.community_id then
        raise exception 'group category not found in community' using errcode = 'OCG01';
    end if;

    -- Return the validated group row
    return new;
end;
$$ language plpgsql;
