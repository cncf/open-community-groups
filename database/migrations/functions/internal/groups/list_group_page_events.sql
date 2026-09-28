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
    ),
    owner_events as (
        select
            g.community_id,
            e.event_id,
            e.group_id,
            e.starts_at
        from event e
        join scoped_groups sg using (group_id)
        join "group" g using (group_id)
        where e.canceled = false
        and e.deleted = false
        and e.event_kind_id = any(p_event_kind_ids)
        and e.published = true
        and e.starts_at is not null
        and e.test_event = false
    ),
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
        and e.canceled = false
        and e.deleted = false
        and e.event_kind_id = any(p_event_kind_ids)
        and e.published = true
        and e.starts_at is not null
        and e.test_event = false
        and owner_community.active = true
        and owner_group.active = true
        and owner_group.deleted = false
    )
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
