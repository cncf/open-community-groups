-- Returns all pending organizer-created event invitations for a user.
create or replace function list_user_event_invitations(p_user_id uuid)
returns json as $$
    select coalesce(json_agg(row_to_json(invitation)), '[]'::json)
    from (
        select
            c.display_name as alliance_display_name,
            c.name as alliance_name,
            e.event_id,
            e.name as event_name,
            g.name as group_name,
            e.timezone,

            extract(epoch from ea.created_at)::bigint as created_at,
            extract(epoch from e.starts_at)::bigint as starts_at
        from event_attendee ea
        join event e using (event_id)
        join "group" g using (group_id)
        join alliance c using (alliance_id)
        where ea.user_id = p_user_id
        and ea.status = 'invitation-pending'
        and g.active = true
        and e.deleted = false
        and e.published = true
        and e.canceled = false
        and (
            coalesce(e.ends_at, e.starts_at) is null
            or coalesce(e.ends_at, e.starts_at) >= current_timestamp
        )
        order by ea.created_at desc
    ) invitation;
$$ language sql;
