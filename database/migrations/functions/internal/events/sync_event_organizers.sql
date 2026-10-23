-- sync_event_organizers replaces an event's organizers with the submitted users, keeping their submitted order.
create or replace function sync_event_organizers(p_event_id uuid, p_organizers jsonb)
returns void as $$
declare
    v_group_id uuid;
begin
    -- Reject payloads that are not JSON arrays
    if jsonb_typeof(p_organizers) is distinct from 'array' then
        raise exception 'invalid organizers payload' using errcode = 'OCG01';
    end if;

    -- Reject array elements that are not UUID strings
    if exists (
        select 1
        from jsonb_array_elements(p_organizers) as organizer(value)
        where jsonb_typeof(organizer.value) <> 'string'
        or (organizer.value #>> '{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ) then
        raise exception 'invalid organizers payload' using errcode = 'OCG01';
    end if;

    -- Load the group whose team members can be organizers
    select group_id
    into v_group_id
    from event
    where event_id = p_event_id;

    -- Reject new organizers outside the accepted group team, while keeping
    -- users already listed as organizers of the event
    if exists (
        select 1
        from jsonb_array_elements_text(p_organizers) as organizer(user_id)
        where not user_is_group_team_member(v_group_id, organizer.user_id::uuid)
        and not exists (
            select 1
            from event_organizer eo
            where eo.event_id = p_event_id
            and eo.user_id = organizer.user_id::uuid
        )
    ) then
        raise exception 'organizer is not a group team member' using errcode = 'OCG01';
    end if;

    -- Remove the stored organizers before writing the submitted list
    delete from event_organizer
    where event_id = p_event_id;

    -- Store each user once at its first submitted position, numbered from one
    insert into event_organizer (event_id, user_id, "order")
    select
        p_event_id,
        organizer.user_id,
        row_number() over (order by organizer.position)::int
    from (
        select
            element.user_id::uuid as user_id,
            min(element.position) as position
        from jsonb_array_elements_text(p_organizers) with ordinality as element(user_id, position)
        group by element.user_id::uuid
    ) organizer;
end;
$$ language plpgsql;
