-- Lists current co-host invitations for an event editor; missing events return an empty result.
create or replace function list_event_cohosts(
    p_group_id uuid,
    p_event_id uuid
)
returns json as $$
    with event_row as (
        select e.cohosts_revision
        from event e
        where e.event_id = p_event_id
        and e.group_id = p_group_id
        and e.deleted = false
    ),
    cohost_rows as (
        select
            c.display_name as community_display_name,
            c.name as community_name,
            c.active and g.active and not g.deleted as group_active,
            g.group_id,
            ec.invitation_id,
            epoch_seconds(ec.invited_at) as invited_at,
            coalesce(g.logo_url, c.logo_url) as logo_url,
            g.name,
            g.slug,
            ec.event_cohost_status_id as status,

            g.slug_pretty
        from event_row er
        join event_cohost ec on ec.event_id = p_event_id
        join "group" g using (group_id)
        join community c using (community_id)
        where ec.event_cohost_status_id in ('approved', 'pending')
        order by g.name asc, g.group_id asc
    ),
    cohosts_json as (
        select coalesce(
            json_agg(jsonb_strip_nulls(to_jsonb(cohost_rows)) order by name asc, group_id asc),
            '[]'::json
        ) as cohosts
        from cohost_rows
    )
    select json_build_object(
        'cohosts', cohosts_json.cohosts,
        'revision', coalesce((select cohosts_revision from event_row), 0)
    )
    from cohosts_json;
$$ language sql stable;
