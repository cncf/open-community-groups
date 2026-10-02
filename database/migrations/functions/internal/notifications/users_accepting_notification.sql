-- Returns the given users who accept a notification kind for the groups it
-- names, with their position in the input array. Kinds without a category are
-- always accepted. Otherwise the category must not be turned off and, for
-- group-mutable categories, none of the named groups may be muted. Group
-- availability is ignored so a mute applies again when its group is
-- reactivated. The planner inlines this set-based rule into its callers as
-- anti-joins, so callers pass plain values or columns rather than subqueries.
create or replace function users_accepting_notification(
    p_kind text,
    p_user_ids uuid[],
    p_group_ids uuid[]
)
returns table (ordinal bigint, user_id uuid) as $$
    select
        r.ordinal,
        r.user_id
    from unnest(p_user_ids) with ordinality as r(user_id, ordinal)
    where not exists (
        select 1
        from user_notification_opt_out uo
        where uo.notification_category_id = (
            select nk.notification_category_id
            from notification_kind nk
            where nk.name = p_kind
        )
        and uo.user_id = r.user_id
    )
    and not exists (
        select 1
        from user_group_notification_mute ugm
        where ugm.group_id = any(p_group_ids)
        and ugm.user_id = r.user_id
        and (
            select nc.group_mutable
            from notification_kind nk
            join notification_category nc using (notification_category_id)
            where nk.name = p_kind
        )
    );
$$ language sql stable;
