-- Updates whether an active user badge is discoverable on profiles.
create or replace function update_user_badge_listing(
    p_actor_user_id uuid,
    p_user_badge_id uuid,
    p_is_listed boolean
)
returns void as $$
begin
    -- Update only an active award owned by the actor
    update user_badge
    set is_listed = p_is_listed
    where user_badge_id = p_user_badge_id
    and user_id = p_actor_user_id
    and revoked_at is null;

    if not found then
        raise exception 'active awarded badge not found';
    end if;
end;
$$ language plpgsql;
