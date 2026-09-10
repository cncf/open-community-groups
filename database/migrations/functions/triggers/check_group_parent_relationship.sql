-- Validates a group's parent link and keeps the hierarchy to one level.
create or replace function check_group_parent_relationship()
returns trigger as $$
declare
    v_parent record;
begin
    -- Allow groups without a parent
    if new.parent_group_id is null then
        return new;
    end if;

    -- Reject direct self-references
    if new.parent_group_id = new.group_id then
        raise exception 'group cannot be its own parent' using errcode = 'OCG01';
    end if;

    -- Preserve existing links, including inactive parents, on unrelated saves
    if tg_op = 'UPDATE'
       and new.parent_group_id is not distinct from old.parent_group_id then
        return new;
    end if;

    -- Load and lock the selected parent for validation
    select
        g.active,
        g.community_id,
        g.deleted,
        g.group_id,
        g.parent_group_id
    into v_parent
    from "group" g
    where g.group_id = new.parent_group_id
    for update;

    -- Reject missing parents
    if not found then
        raise exception 'parent group not found' using errcode = 'OCG01';
    end if;

    -- Reject parents from another community
    if v_parent.community_id <> new.community_id then
        raise exception 'parent group must belong to the same community' using errcode = 'OCG01';
    end if;

    -- Reject deleted parents
    if v_parent.deleted then
        raise exception 'parent group cannot be deleted' using errcode = 'OCG01';
    end if;

    -- Reject inactive parents
    if not v_parent.active then
        raise exception 'parent group must be active' using errcode = 'OCG01';
    end if;

    -- Reject parents that are themselves subgroups
    if v_parent.parent_group_id is not null then
        raise exception 'parent group cannot be a subgroup' using errcode = 'OCG01';
    end if;

    -- Prevent multi-level hierarchy from the child side
    if exists (
        select 1
        from "group" child
        where child.parent_group_id = new.group_id
        and child.deleted = false
        and child.group_id <> new.group_id
    ) then
        raise exception 'group with subgroups cannot have a parent' using errcode = 'OCG01';
    end if;

    -- Return the validated group row
    return new;
end;
$$ language plpgsql;
