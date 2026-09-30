-- Returns the available groups a user is connected to: groups they belong to
-- or help organize, and the owner and approved co-host groups of events they
-- are registered for, waitlisted on, or speak at.
create or replace function list_user_notification_group_ids(p_user_id uuid)
returns uuid[] as $$
    with
        -- Collect the events the user is attending, waiting for, or speaking at
        user_events as (
            select ea.event_id
            from event_attendee ea
            where ea.user_id = p_user_id

            union

            select ew.event_id
            from event_waitlist ew
            where ew.user_id = p_user_id

            union

            select es.event_id
            from event_speaker es
            where es.user_id = p_user_id

            union

            select s.event_id
            from session_speaker ss
            join session s using (session_id)
            where ss.user_id = p_user_id
        ),
        -- Collect groups connected through membership, teams, and events
        connected_groups as (
            select gm.group_id
            from group_member gm
            where gm.user_id = p_user_id

            union

            select gt.group_id
            from group_team gt
            where gt.accepted = true
            and gt.user_id = p_user_id

            union

            select e.group_id
            from user_events ue
            join event e using (event_id)
            where e.deleted = false

            union

            select ec.group_id
            from user_events ue
            join event e using (event_id)
            join event_cohost ec on ec.event_id = e.event_id
            where e.deleted = false
            and ec.event_cohost_status_id = 'approved'
        )
    -- Keep groups that are available in an active community
    select coalesce(array_agg(g.group_id order by g.group_id), '{}'::uuid[])
    from connected_groups cg
    join "group" g using (group_id)
    join community c using (community_id)
    where c.active = true
    and g.active = true
    and g.deleted = false;
$$ language sql stable;
