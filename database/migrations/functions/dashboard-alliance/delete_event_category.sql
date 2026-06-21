-- Deletes an event category from a alliance when not in use.
create or replace function delete_event_category(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_event_category_id uuid
)
returns void as $$
declare
    v_events_count bigint;
    v_name text;
begin
    -- Ensure the event category exists in the selected alliance, snapshotting
    -- its name so the audit row remains readable after deletion
    select ec.name
    into v_name
    from event_category ec
    where ec.alliance_id = p_alliance_id
      and ec.event_category_id = p_event_category_id;

    if not found then
        raise exception 'event category not found';
    end if;

    -- Block deletion when events still reference this category
    select count(*)
    into v_events_count
    from event e
    where e.event_category_id = p_event_category_id;

    if v_events_count > 0 then
        raise exception 'cannot delete event category in use by events';
    end if;

    -- Delete the category record
    delete from event_category ec
    where ec.alliance_id = p_alliance_id
      and ec.event_category_id = p_event_category_id;

    -- Track the deletion
    perform insert_audit_log(
        'event_category_deleted',
        p_actor_user_id,
        'event_category',
        p_event_category_id,
        p_alliance_id,
        null,
        null,
        jsonb_build_object('name', v_name)
    );
end;
$$ language plpgsql;
