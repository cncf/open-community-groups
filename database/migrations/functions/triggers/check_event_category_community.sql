-- Rejects events whose category belongs to another community than their group.
create or replace function check_event_category_community()
returns trigger as $$
declare
    v_category_community_id uuid;
    v_group_community_id uuid;
begin
    -- Resolve the community that owns the event group
    select community_id into v_group_community_id
    from "group"
    where group_id = new.group_id;

    -- Resolve the community that owns the event category
    select community_id into v_category_community_id
    from event_category
    where event_category_id = new.event_category_id;

    -- Reject categories from another community
    if v_category_community_id is distinct from v_group_community_id then
        raise exception 'event category not found in community' using errcode = 'OCG01';
    end if;

    -- Return the validated event row
    return new;
end;
$$ language plpgsql;
