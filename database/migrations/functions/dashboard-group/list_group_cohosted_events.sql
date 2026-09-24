-- Returns paginated co-host invitations and credited events for a group dashboard.
create or replace function list_group_cohosted_events(
    p_group_id uuid,
    p_filters jsonb
)
returns json as $$
    with
        -- Parse pagination filters
        filters as (
            select
                coalesce(f.limit_value, 50) as limit_value,
                coalesce(f.offset_value, 0) as offset_value
            from parse_search_filters(p_filters) f
        ),
        -- Select co-host rows whose events still exist
        base_events as (
            select
                e.canceled,
                e.ends_at,
                e.event_id,
                e.event_kind_id as event_kind,
                coalesce(e.logo_url, owner_group.logo_url, owner_community.logo_url) as event_logo_url,
                e.name as event_name,
                e.slug as event_slug,
                ec.invitation_id,
                ec.invited_at,
                owner_community.display_name as owner_community_display_name,
                owner_community.name as owner_community_name,
                coalesce(owner_group.logo_url, owner_community.logo_url) as owner_group_logo_url,
                owner_group.name as owner_group_name,
                owner_group.slug as owner_group_slug,
                e.published,
                ec.responded_at,
                e.starts_at,
                ec.event_cohost_status_id as status,
                e.timezone,

                owner_group.slug_pretty as owner_group_slug_pretty
            from event_cohost ec
            join event e using (event_id)
            join "group" owner_group on owner_group.group_id = e.group_id
            join community owner_community on owner_community.community_id = owner_group.community_id
            where ec.group_id = p_group_id
            and e.deleted = false
        ),
        -- Count rows before pagination
        totals as (
            select count(*)::int as total
            from base_events
        ),
        -- Select the requested page
        paged_events as (
            select *
            from base_events
            order by starts_at desc nulls last, event_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Render rows with nullable fields stripped consistently
        events_json as (
            select coalesce(
                json_agg(
                    jsonb_strip_nulls(jsonb_build_object(
                        'canceled', canceled,
                        'event_id', event_id,
                        'event_kind', event_kind,
                        'event_logo_url', event_logo_url,
                        'event_name', event_name,
                        'event_slug', event_slug,
                        'invitation_id', invitation_id,
                        'invited_at', epoch_seconds(invited_at),
                        'owner_community_display_name', owner_community_display_name,
                        'owner_community_name', owner_community_name,
                        'owner_group_logo_url', owner_group_logo_url,
                        'owner_group_name', owner_group_name,
                        'owner_group_slug', owner_group_slug,
                        'published', published,
                        'status', status,
                        'timezone', timezone,

                        'ends_at', epoch_seconds(ends_at),
                        'owner_group_slug_pretty', owner_group_slug_pretty,
                        'responded_at', epoch_seconds(responded_at),
                        'starts_at', epoch_seconds(starts_at)
                    ))
                    order by starts_at desc nulls last, event_id asc
                ),
                '[]'::json
            ) as events
            from paged_events
        )
    -- Build final payload
    select json_build_object(
        'events', events_json.events,
        'total', totals.total
    )
    from events_json, totals;
$$ language sql stable;
