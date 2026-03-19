-- Get a user's attendance details for an event, including check-in status.
create or replace function get_event_attendance(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
) returns json as $$
    with scoped_event as (
        select e.event_id
        from event e
        join "group" g on g.group_id = e.group_id
        where e.event_id = p_event_id
        and g.community_id = p_community_id
        and g.active = true
        and e.deleted = false
        and e.published = true
        and e.canceled = false
        and (
            -- Keep started events without an end time readable for check-in and status views
            -- even though attend_event and leave_event treat them as inactive for mutations
            e.ends_at is null
            or e.ends_at >= current_timestamp
        )
    ),
    attendance_state as (
        select
            coalesce(
                (
                    select bool_and(ea.checked_in)
                    from event_attendee ea
                    where ea.event_id = p_event_id
                    and ea.user_id = p_user_id
                    and exists (select 1 from scoped_event)
                ),
                false
            ) as is_checked_in,
            case
                when exists (
                    select 1
                    from event_attendee ea
                    where ea.event_id = p_event_id
                    and ea.user_id = p_user_id
                    and exists (select 1 from scoped_event)
                ) then 'attendee'
                when exists (
                    select 1
                    from event_waitlist ew
                    where ew.event_id = p_event_id
                    and ew.user_id = p_user_id
                    and exists (select 1 from scoped_event)
                ) then 'waitlisted'
                else 'none'
            end as status
    )
    select
        json_build_object(
            'is_checked_in', is_checked_in,
            'status', status
        )
    from attendance_state;
$$ language sql;
