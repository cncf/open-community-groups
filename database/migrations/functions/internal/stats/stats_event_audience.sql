-- Returns audience composition and registration answer breakdowns for an event.
--
-- The membership window opens at the registration start, or at the
-- publication when unset, and closes as registration_window_closes_at
-- decides, capped at the effective event end and at the observation time.
create or replace function stats_event_audience(p_event event)
returns json as $$
with registration_window as (
    select
        window_close.closes_at,
        least(
            window_close.closes_at,
            event_effective_ends_at(p_event),
            current_timestamp
        ) as ends_at,
        coalesce(p_event.registration_starts_at, p_event.published_at) as starts_at
    from (
        select registration_window_closes_at(
            p_event.registration_starts_at,
            p_event.registration_ends_at,
            p_event.starts_at
        ) as closes_at
    ) window_close
),
membership_window as (
    select
        rw.ends_at,
        rw.starts_at
    from registration_window rw
    where rw.starts_at < rw.ends_at
),
attendees as (
    select
        ea.registration_answers,
        ea.user_id
    from event_attendee ea
    where ea.event_id = p_event.event_id
    and ea.status = 'confirmed'
),
returning_attendees as (
    select a.user_id
    from attendees a
    where exists (
        select 1
        from event_attendee pa
        join event pe on pe.event_id = pa.event_id
        where pa.user_id = a.user_id
        and pa.status = 'confirmed'
        and pe.canceled = false
        and pe.deleted = false
        and pe.event_id <> p_event.event_id
        and pe.group_id = p_event.group_id
        and pe.starts_at < p_event.starts_at
        and pe.test_event = false
    )
),
window_members as (
    select gm.user_id
    from group_member gm
    join membership_window mw
        on gm.created_at >= mw.starts_at
        and gm.created_at < mw.ends_at
    where gm.group_id = p_event.group_id
),
questions as (
    select
        question.position,
        question.definition
    from jsonb_array_elements(p_event.registration_questions)
        with ordinality as question(definition, position)
    where question.definition->>'kind' in ('multi-select', 'single-select')
),
selections as (
    select
        case
            when pg_input_is_valid(selected.value, 'uuid') then selected.value::uuid
        end as option_id,
        (answer.value->>'question_id')::uuid as question_id,
        a.user_id
    from attendees a
    cross join lateral jsonb_array_elements(
        case
            when jsonb_typeof(a.registration_answers->'answers') = 'array'
                then a.registration_answers->'answers'
            else '[]'::jsonb
        end
    ) as answer(value)
    cross join lateral (
        select answer.value->>'value' as value
        where jsonb_typeof(answer.value->'value') = 'string'

        union all

        select option_value #>> '{}' as value
        from jsonb_array_elements(
            case
                when jsonb_typeof(answer.value->'value') = 'array' then answer.value->'value'
                else '[]'::jsonb
            end
        ) as option_value
    ) selected
),
option_selections as (
    select
        (question_option.definition->>'id')::uuid as option_id,
        q.position,
        s.user_id
    from questions q
    cross join lateral jsonb_array_elements(q.definition->'options')
        as question_option(definition)
    join selections s
        on s.question_id = (q.definition->>'id')::uuid
        and s.option_id = (question_option.definition->>'id')::uuid
),
question_breakdowns as (
    select
        json_build_object(
            'kind', q.definition->>'kind',
            'options', coalesce((
                select json_agg(
                    json_build_object(
                        'count', (
                            select count(*)
                            from option_selections os
                            where os.position = q.position
                            and os.option_id = (question_option.definition->>'id')::uuid
                        ),
                        'label', question_option.definition->>'label',
                        'option_id', (question_option.definition->>'id')::uuid
                    )
                    order by question_option.position
                )
                from jsonb_array_elements(q.definition->'options')
                    with ordinality as question_option(definition, position)
            ), '[]'::json),
            'prompt', q.definition->>'prompt',
            'question_id', (q.definition->>'id')::uuid,
            'respondents', (
                select count(distinct os.user_id)
                from option_selections os
                where os.position = q.position
            ),
            'selections', (
                select count(*)
                from option_selections os
                where os.position = q.position
            )
        ) as breakdown,
        q.position
    from questions q
)
select json_build_object(
    'questions', coalesce((
        select json_agg(qb.breakdown order by qb.position)
        from question_breakdowns qb
    ), '[]'::json),
    'window_end_capped', coalesce(rw.ends_at < rw.closes_at, false),
    'window_end_inferred', rw.closes_at is null,
    'window_start_inferred', p_event.registration_starts_at is null,

    'members_joined_in_window', case
        when mw.starts_at is not null then (select count(*) from window_members)
    end,
    'members_joined_in_window_registered', case
        when mw.starts_at is not null then (
            select count(*)
            from window_members wm
            where exists (select 1 from attendees a where a.user_id = wm.user_id)
        )
    end,
    'new_attendees', case
        when p_event.starts_at is not null then (
            select count(*)
            from attendees a
            where not exists (select 1 from returning_attendees ra where ra.user_id = a.user_id)
        )
    end,
    'returning_attendees', case
        when p_event.starts_at is not null then (select count(*) from returning_attendees)
    end,
    'window_ends_at', epoch_seconds(mw.ends_at),
    'window_starts_at', epoch_seconds(mw.starts_at)
)
from registration_window rw
left join membership_window mw on true;
$$ language sql stable;
