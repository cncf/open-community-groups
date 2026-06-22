-- Updates an event category in a alliance.
create or replace function update_event_category(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_event_category_id uuid,
    p_event_category jsonb
)
returns void as $$
begin
    -- Ensure the target category exists in the selected alliance
    perform 1
    from event_category ec
    where ec.alliance_id = p_alliance_id
      and ec.event_category_id = p_event_category_id;

    if not found then
        raise exception 'event category not found';
    end if;

    -- Update the category record
    update event_category set
        name = p_event_category->>'name'
    where alliance_id = p_alliance_id
      and event_category_id = p_event_category_id;

    -- Track the updated category
    perform insert_audit_log(
        'event_category_updated',
        p_actor_user_id,
        'event_category',
        p_event_category_id,
        p_alliance_id
    );
exception
    when unique_violation then
        raise exception 'event category already exists';
    when check_violation then
        raise exception 'event category name is invalid';
end;
$$ language plpgsql;
