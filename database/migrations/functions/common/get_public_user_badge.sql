-- Returns a durable public badge credential record by opaque award identifier.
create or replace function get_public_user_badge(p_user_badge_id uuid)
returns json as $$
    select (
        user_badge_json(ub, true)
        || jsonb_build_object(
            'recipient_name', u.name,
            'recipient_username', u.username
        )
    )::json
    from user_badge ub
    left join "user" u using (user_id)
    where ub.user_badge_id = p_user_badge_id;
$$ language sql stable;
