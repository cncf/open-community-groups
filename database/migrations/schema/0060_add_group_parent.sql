-- Add a single-level parent relationship between groups.

-- Store optional parent links
alter table "group"
add column parent_group_id uuid references "group";

create index group_parent_group_id_idx on "group" (parent_group_id);

-- Replace the old stats signature with the subgroup-aware version
drop function if exists get_group_stats(uuid, uuid);

-- Checks that a group parent relationship stays single-level and visible.
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
        raise exception 'group cannot be its own parent';
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

    if not found then
        raise exception 'parent group not found';
    end if;

    -- Validate parent ownership and visibility
    if v_parent.community_id <> new.community_id then
        raise exception 'parent group must belong to the same community';
    end if;

    if v_parent.deleted then
        raise exception 'parent group cannot be deleted';
    end if;

    if not v_parent.active then
        raise exception 'parent group must be active';
    end if;

    if v_parent.parent_group_id is not null then
        raise exception 'parent group cannot be a subgroup';
    end if;

    -- Prevent multi-level hierarchy from the child side
    if exists (
        select 1
        from "group" child
        where child.parent_group_id = new.group_id
        and child.deleted = false
        and child.group_id <> new.group_id
    ) then
        raise exception 'group with subgroups cannot have a parent';
    end if;

    return new;
end;
$$ language plpgsql;

-- Enforce parent-child invariants on relationship changes
create trigger group_parent_relationship_check
before insert or update of parent_group_id on "group"
for each row
execute function check_group_parent_relationship();
