-- Adds a new alliance and assigns the actor as its initial admin.
create or replace function add_alliance(
    p_actor_user_id uuid,
    p_alliance jsonb
)
returns uuid as $$
declare
    v_alliance_id uuid;
begin
    if not exists (
        select 1
        from "user" u
        where u.user_id = p_actor_user_id
        and u.platform_admin = true
    ) then
        raise exception 'platform admin permission required';
    end if;

    insert into alliance (
        name,
        display_name,
        description,
        banner_url,
        banner_mobile_url,
        logo_url,
        website_url
    ) values (
        lower(trim(p_alliance->>'name')),
        trim(p_alliance->>'display_name'),
        trim(p_alliance->>'description'),
        trim(p_alliance->>'banner_url'),
        trim(p_alliance->>'banner_mobile_url'),
        trim(p_alliance->>'logo_url'),
        nullif(trim(p_alliance->>'website_url'), '')
    )
    returning alliance_id into v_alliance_id;

    insert into alliance_team (
        alliance_id,
        user_id,
        accepted,
        role
    ) values (
        v_alliance_id,
        p_actor_user_id,
        true,
        'admin'
    );

    insert into group_category (alliance_id, name)
    values (v_alliance_id, 'General');

    insert into event_category (alliance_id, name)
    values (v_alliance_id, 'General');

    insert into region (alliance_id, name)
    values (v_alliance_id, 'Global');

    perform insert_audit_log(
        'alliance_added',
        p_actor_user_id,
        'alliance',
        v_alliance_id,
        v_alliance_id
    );

    return v_alliance_id;
exception
    when unique_violation then
        raise exception 'alliance already exists';
    when check_violation then
        raise exception 'alliance input is invalid';
end;
$$ language plpgsql;
