-- Lists owner and approved co-hosted events in a group's public page scope.
create or replace function list_group_page_events(
    p_community_id uuid,
    p_group_slug text,
    p_event_kind_ids text[]
)
returns table (
    community_id uuid,
    event_id uuid,
    group_id uuid,
    starts_at timestamptz
) as $$
    with
    -- Resolve the publicly visible group whose page is listed
    target_group as (
        select g.group_id
        from "group" g
        where g.community_id = p_community_id
        and (g.slug = p_group_slug or g.slug_pretty = p_group_slug)
        and is_group_public(g)
    ),
    -- Scope the page to the target group and its public subgroups
    scoped_groups as (
        select s.group_id
        from target_group tg
        cross join lateral list_group_scope_ids(p_community_id, tg.group_id, true) s
    ),
    -- Collect listed events owned by the scoped groups
    owner_events as (
        select
            g.community_id,
            e.event_id,
            e.group_id,
            e.starts_at
        from event e
        join scoped_groups sg using (group_id)
        join "group" g using (group_id)
        where is_event_listed(e, g)
        and e.event_kind_id = any(p_event_kind_ids)
        and e.starts_at is not null
    ),
    -- Collect listed events of public owners co-hosted by the target group
    cohosted_events as (
        select
            owner_community.community_id,
            e.event_id,
            e.group_id,
            e.starts_at
        from target_group tg
        join event_cohost ec on ec.group_id = tg.group_id
        join event e using (event_id)
        join "group" owner_group on owner_group.group_id = e.group_id
        join community owner_community on owner_community.community_id = owner_group.community_id
        where ec.event_cohost_status_id = 'approved'
        and is_event_listed(e, owner_group)
        and e.event_kind_id = any(p_event_kind_ids)
        and e.starts_at is not null
        and owner_community.active = true
    )
    -- Return each page event once with its owner community
    select distinct
        page_events.community_id,
        page_events.event_id,
        page_events.group_id,
        page_events.starts_at
    from (
        select *
        from owner_events

        union all

        select *
        from cohosted_events
    ) page_events;
$$ language sql stable;
