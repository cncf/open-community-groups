-- Projects a discount codes payload onto the configuration compared by
-- event_ticketing_configuration_changed, resolving each submitted code
-- against the stored code with the same identifier: the override flag and
-- Uses remaining follow the persisted rule (resolve_event_discount_code_
-- available_override; an omitted count keeps the stored live inventory; the
-- count is dropped once the override is off), the API-only available_cleared
-- command is dropped, an omitted active flag defaults to true, schedules are
-- normalized through normalize_ticketing_schedule and codes are ordered by
-- identifier so editor sorting never registers as a change. Projecting the
-- stored codes against themselves is the identity, so both sides compare
-- symmetrically. Comparison-only; never written back.
create or replace function event_discount_codes_configuration(
    p_discount_codes jsonb,
    p_stored_discount_codes jsonb
)
returns jsonb as $$
    select coalesce(
        jsonb_agg(
            normalize_ticketing_schedule(
                (codes.discount_code - 'available' - 'available_cleared' - 'available_override_active')
                || jsonb_build_object(
                    'active', coalesce(nullif(codes.discount_code->'active', 'null'::jsonb), 'true'::jsonb),
                    'available', case
                        -- Keep the submitted count or the stored live inventory while the override is on
                        when overrides.override_active then coalesce(
                            nullif(codes.discount_code->'available', 'null'::jsonb),
                            stored.discount_code->'available'
                        )
                        -- Drop the count once the override is off
                        else null
                    end,
                    'available_override_active', overrides.override_active
                )
            )
            order by (codes.discount_code->>'event_discount_code_id')::uuid, codes.ordinality
        ),
        '[]'::jsonb
    )
    from jsonb_array_elements(coalesce(nullif(p_discount_codes, 'null'::jsonb), '[]'::jsonb))
        with ordinality as codes(discount_code, ordinality)
    left join lateral (
        select stored_codes.discount_code
        from jsonb_array_elements(coalesce(nullif(p_stored_discount_codes, 'null'::jsonb), '[]'::jsonb))
            as stored_codes(discount_code)
        where (stored_codes.discount_code->>'event_discount_code_id')::uuid
            = (codes.discount_code->>'event_discount_code_id')::uuid
        limit 1
    ) as stored on true
    cross join lateral (
        select resolve_event_discount_code_available_override(
            codes.discount_code,
            coalesce((stored.discount_code->>'available_override_active')::boolean, false)
        ) as override_active
    ) as overrides;
$$ language sql stable;
