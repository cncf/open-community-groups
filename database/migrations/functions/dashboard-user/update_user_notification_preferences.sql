-- Updates the submitted notification category preferences for a user.
-- Categories not included in the payload keep their current state.
create or replace function update_user_notification_preferences(
    p_actor_user_id uuid,
    p_preferences jsonb
)
returns void as $$
declare
    v_opted_out_categories jsonb;
begin
    -- Require an object of category preferences
    if p_preferences is null or jsonb_typeof(p_preferences) <> 'object' then
        raise exception 'invalid notification preferences' using errcode = 'OCG01';
    end if;

    -- Reject categories that do not exist
    if exists (
        select 1
        from jsonb_object_keys(p_preferences) as pk(notification_category_id)
        left join notification_category nc using (notification_category_id)
        where nc.notification_category_id is null
    ) then
        raise exception 'unknown notification category' using errcode = 'OCG01';
    end if;

    -- Reject preference values that are not booleans
    if exists (
        select 1
        from jsonb_each(p_preferences) p
        where jsonb_typeof(p.value) <> 'boolean'
    ) then
        raise exception 'invalid notification preferences' using errcode = 'OCG01';
    end if;

    -- Turn on the categories submitted as enabled
    delete from user_notification_opt_out uo
    using jsonb_each(p_preferences) p
    where uo.notification_category_id = p.key
    and uo.user_id = p_actor_user_id
    and p.value = 'true'::jsonb;

    -- Turn off the categories submitted as disabled
    insert into user_notification_opt_out (notification_category_id, user_id)
    select p.key, p_actor_user_id
    from jsonb_each(p_preferences) p
    where p.value = 'false'::jsonb
    on conflict (user_id, notification_category_id) do nothing;

    -- Snapshot the resulting opt-outs for the audit trail
    select coalesce(
        jsonb_agg(uo.notification_category_id order by uo.notification_category_id),
        '[]'::jsonb
    )
    into v_opted_out_categories
    from user_notification_opt_out uo
    where uo.user_id = p_actor_user_id;

    -- Track the preferences update
    perform insert_audit_log(
        'user_notification_preferences_updated',
        p_actor_user_id,
        'user',
        p_actor_user_id,
        p_details => jsonb_build_object('opted_out_categories', v_opted_out_categories)
    );
end;
$$ language plpgsql;
