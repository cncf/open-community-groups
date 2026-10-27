-- Deletes an event category from a community when not in use.
create or replace function delete_event_category(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_event_category_id uuid
)
returns void as $$
declare
    v_name text;
begin
    -- Lock the category and snapshot its name for the audit row
    select ec.name
    into v_name
    from event_category ec
    where ec.community_id = p_community_id
      and ec.event_category_id = p_event_category_id
    for update of ec;

    -- Reject categories outside the selected community
    if not found then
        raise exception 'event category not found' using errcode = 'OCG01';
    end if;

    -- Reject categories still used by any events, including deleted ones
    if exists (
        select 1
        from event e
        where e.event_category_id = p_event_category_id
    ) then
        raise exception 'cannot delete event category in use by events' using errcode = 'OCG01';
    end if;

    -- Delete the category record
    delete from event_category ec
    where ec.community_id = p_community_id
      and ec.event_category_id = p_event_category_id;

    -- Track the deletion
    perform insert_audit_log(
        'event_category_deleted',
        p_actor_user_id,
        'event_category',
        p_event_category_id,
        p_community_id,
        null,
        null,
        jsonb_build_object('name', v_name)
    );
end;
$$ language plpgsql;
