-- Returns the number of pending team invitations and active event offers listed
-- in a user's Invitations tab.
-- Uses PL/pgSQL with `force_generic_plan` so each connection caches its plan
-- instead of planning the SQL-language body on every call.
create or replace function count_user_pending_invitations(p_user_id uuid)
returns int as $$
begin
    -- Count pending team invitations and claimable event offers
    return (
        select (
            (
                select count(*)
                from community_team ct
                where ct.user_id = p_user_id
                and ct.accepted = false
            )
            + (
                select count(*)
                from group_team gt
                where gt.user_id = p_user_id
                and gt.accepted = false
            )
            + (
                select count(*)
                from admission_offer ao
                join event e using (event_id)
                join "group" g using (group_id)
                where ao.user_id = p_user_id
                and admission_offer_is_claimable(ao)
                and event_accepts_enrollment(e, g)
            )
        )::int
    );
end;
$$ language plpgsql stable set plan_cache_mode = force_generic_plan;
