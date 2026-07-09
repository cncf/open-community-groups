-- Lists possible parent groups for a group relationship field.
create or replace function list_group_parent_options(
    p_community_id uuid,
    p_user_id uuid,
    p_group_id uuid
) returns json as $$
    with current_group as (
        -- Preserve the existing parent option for no-op saves
        select g.parent_group_id
        from "group" g
        where g.community_id = p_community_id
        and g.group_id = p_group_id
        and g.deleted = false
    ),
    selectable_parents as (
        -- List active top-level groups the user can newly select
        select
            g.active,
            g.group_id,
            false as is_current,
            true as is_selectable,
            g.name
        from "group" g
        where g.community_id = p_community_id
        and g.active = true
        and g.deleted = false
        and g.parent_group_id is null
        and (p_group_id is null or g.group_id <> p_group_id)
        and user_has_group_permission(
            p_community_id,
            g.group_id,
            p_user_id,
            'group.settings.write'
        )
    ),
    current_parent as (
        -- Include the current parent when it is no longer selectable
        select
            parent.active,
            parent.group_id,
            true as is_current,
            false as is_selectable,
            parent.name
        from current_group cg
        join "group" parent on parent.group_id = cg.parent_group_id
        where parent.community_id = p_community_id
        and parent.deleted = false
        and not exists (
            select 1
            from selectable_parents sp
            where sp.group_id = parent.group_id
        )
    ),
    parent_options as (
        -- Merge selectable options with the preservation-only current option
        select *
        from selectable_parents

        union all

        select *
        from current_parent
    )
    -- Return a deterministic JSON array for dashboard selects
    select coalesce(json_agg(json_build_object(
        'active', active,
        'group_id', group_id,
        'is_current', is_current,
        'is_selectable', is_selectable,
        'name', name
    ) order by is_selectable desc, name asc, group_id asc), '[]'::json)
    from parent_options;
$$ language sql stable;
