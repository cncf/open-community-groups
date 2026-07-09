-- Returns past events for a specific group.
create or replace function get_group_past_events(
    p_community_id uuid,
    p_group_slug text,
    p_event_kind_ids text[],
    p_limit int
) returns json as $$
    with target_group as (
        select g.group_id
        from "group" g
        where g.community_id = p_community_id
        and (g.slug = p_group_slug or g.slug_pretty = p_group_slug)
        and g.active = true
        and g.deleted = false
    ),
    scoped_groups as (
        select tg.group_id
        from target_group tg

        union all

        select child.group_id
        from "group" child
        join target_group tg on child.parent_group_id = tg.group_id
        where child.community_id = p_community_id
        and child.active = true
        and child.deleted = false
    )
    select coalesce(json_agg(
        get_event_summary(p_community_id, e.group_id, e.event_id)
        order by e.starts_at desc, e.event_id asc
    ), '[]')
    from (
        select e.event_id, e.group_id, e.starts_at
        from event e
        join scoped_groups sg using (group_id)
        where e.deleted = false
        and e.published = true
        and e.test_event = false
        and e.event_kind_id = any(p_event_kind_ids)
        and e.starts_at is not null
        and e.starts_at <= now()
        and e.canceled = false
        order by e.starts_at desc, e.event_id asc
        limit p_limit
    ) e;
$$ language sql;
