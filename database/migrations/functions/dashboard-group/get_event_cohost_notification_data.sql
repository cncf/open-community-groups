-- Returns notification payload data for co-host event/group pairs.
create or replace function get_event_cohost_notification_data(p_items jsonb)
returns json as $$
    with requested_items as (
        select distinct
            item.cohost_group_id,
            item.event_id
        from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb)) as item(
            event_id uuid,
            cohost_group_id uuid
        )
    ),
    payload_rows as (
        select
            e.canceled,
            cohost_community.display_name as cohost_community_display_name,
            cohost_group.group_id as cohost_group_id,
            cohost_group.name as cohost_group_name,
            e.event_id,
            e.name as event_name,
            ec.invitation_id,
            owner_community.display_name as owner_community_display_name,
            owner_community.community_id as owner_community_id,
            owner_group.group_id as owner_group_id,
            owner_group.name as owner_group_name,
            ec.event_cohost_status_id as status,
            e.timezone,

            epoch_seconds(e.starts_at) as starts_at
        from requested_items ri
        join event_cohost ec
            on ec.event_id = ri.event_id
            and ec.group_id = ri.cohost_group_id
        join event e on e.event_id = ec.event_id
        join "group" owner_group on owner_group.group_id = e.group_id
        join community owner_community on owner_community.community_id = owner_group.community_id
        join "group" cohost_group on cohost_group.group_id = ec.group_id
        join community cohost_community on cohost_community.community_id = cohost_group.community_id
        order by cohost_group.name asc, e.starts_at asc nulls last, e.event_id asc
    )
    select coalesce(
        json_agg(jsonb_strip_nulls(to_jsonb(payload_rows))),
        '[]'::json
    )
    from payload_rows;
$$ language sql stable;
