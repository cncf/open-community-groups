-- list_event_discount_codes returns normalized event discount codes as JSON.
create or replace function list_event_discount_codes(p_event_id uuid)
returns jsonb as $$
    select nullif(
        coalesce(
            jsonb_agg(
                jsonb_strip_nulls(
                    jsonb_build_object(
                        'active', edc.active,
                        'amount_minor', edc.amount_minor,
                        'available', edc.available,
                        'available_override_active', edc.available_override_active,
                        'code', edc.code,
                        'ends_at', edc.ends_at,
                        'event_discount_code_id', edc.event_discount_code_id,
                        'kind', edc.kind,
                        'percentage', edc.percentage,
                        'starts_at', edc.starts_at,
                        'title', edc.title,
                        'total_available', edc.total_available
                    )
                )
                order by edc.title asc, edc.event_discount_code_id asc
            ),
            '[]'::jsonb
        ),
        '[]'::jsonb
    )
    from event_discount_code edc
    where edc.event_id = p_event_id;
$$ language sql;
