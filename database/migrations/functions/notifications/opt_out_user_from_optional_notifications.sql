-- Opts a user out of every notification category, for operators handling
-- addresses on SMTP suppression lists. It covers the categories that exist
-- when it runs; categories added later are not turned off. Returns the number
-- of categories newly turned off.
create or replace function opt_out_user_from_optional_notifications(
    p_email text,
    p_reason text
)
returns integer as $$
declare
    v_notification_category_ids text[];
    v_user_id uuid;
begin
    -- Require the email address to suppress
    if p_email is null or btrim(p_email) = '' then
        raise exception 'email is required';
    end if;

    -- Require the operator reason
    if p_reason is null or btrim(p_reason) = '' then
        raise exception 'suppression reason is required';
    end if;

    -- Resolve the user by email address
    select u.user_id
    into v_user_id
    from "user" u
    where lower(u.email) = lower(btrim(p_email));

    -- Reject addresses without an account
    if not found then
        raise exception 'user not found';
    end if;

    -- Turn off every category the user still receives
    with inserted as (
        insert into user_notification_opt_out (notification_category_id, user_id)
        select nc.notification_category_id, v_user_id
        from notification_category nc
        on conflict (user_id, notification_category_id) do nothing
        returning notification_category_id
    )
    select coalesce(array_agg(i.notification_category_id order by i.notification_category_id), '{}')
    into v_notification_category_ids
    from inserted i;

    -- Record the operator action when categories were turned off
    if cardinality(v_notification_category_ids) > 0 then
        perform insert_audit_log(
            p_action => 'user_notifications_suppressed',
            p_actor_user_id => null,
            p_resource_type => 'user',
            p_resource_id => v_user_id,
            p_details => jsonb_build_object(
                'database_user', current_user,
                'notification_category_ids', to_jsonb(v_notification_category_ids),
                'reason', p_reason
            )
        );
    end if;

    -- Return the number of categories turned off
    return cardinality(v_notification_category_ids);
end;
$$ language plpgsql;
