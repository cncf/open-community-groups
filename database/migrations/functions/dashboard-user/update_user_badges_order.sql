-- Reorders every active badge owned by a dashboard user.
create or replace function update_user_badges_order(
    p_actor_user_id uuid,
    p_user_badge_ids uuid[]
)
returns void as $$
begin
    -- Serialize the actor's complete active badge order
    perform 1
    from "user"
    where user_id = p_actor_user_id
    for update;

    if not found then
        raise exception 'badge owner not found';
    end if;

    -- Validate the supplied identifiers form the actor's complete active set
    if p_user_badge_ids is null
    or cardinality(p_user_badge_ids) <> (
        select count(*)
        from user_badge
        where user_id = p_actor_user_id
        and revoked_at is null
    )
    or cardinality(p_user_badge_ids) <> (
        select count(distinct requested.user_badge_id)
        from unnest(p_user_badge_ids) requested(user_badge_id)
    )
    or exists (
        select 1
        from unnest(p_user_badge_ids) requested(user_badge_id)
        where not exists (
            select 1
            from user_badge ub
            where ub.user_badge_id = requested.user_badge_id
            and ub.user_id = p_actor_user_id
            and ub.revoked_at is null
        )
    ) then
        raise exception 'badge order does not match active badges';
    end if;

    -- Persist the complete zero-based order in one statement
    update user_badge ub
    set display_order = (requested.display_order - 1)::integer
    from unnest(p_user_badge_ids) with ordinality
        requested(user_badge_id, display_order)
    where ub.user_badge_id = requested.user_badge_id
    and ub.user_id = p_actor_user_id
    and ub.revoked_at is null;
end;
$$ language plpgsql;
