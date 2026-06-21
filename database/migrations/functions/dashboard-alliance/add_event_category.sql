-- Adds a new event category to a alliance.
create or replace function add_event_category(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_event_category jsonb
)
returns uuid as $$
declare
    v_event_category_id uuid;
begin
    -- Insert the category record
    insert into event_category (
        alliance_id,
        name
    ) values (
        p_alliance_id,
        p_event_category->>'name'
    )
    returning event_category_id into v_event_category_id;

    -- Track the created category
    perform insert_audit_log(
        'event_category_added',
        p_actor_user_id,
        'event_category',
        v_event_category_id,
        p_alliance_id
    );

    return v_event_category_id;
exception
    when unique_violation then
        raise exception 'event category already exists';
    when check_violation then
        raise exception 'event category name is invalid';
end;
$$ language plpgsql;
