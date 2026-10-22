-- Returns the responses of a survey of a group event for the CSV export, in
-- creation order, with the survey title, anonymity and questions. Respondent
-- name, company, title and username are only returned for identified
-- surveys. Null when the survey does not belong to the group event.
--
-- The function is stable, so the size check (responses and bytes of answers)
-- and the returned rows read the same snapshot. Exports above either bound
-- are rejected before any output is built.
create or replace function get_event_survey_export(
    p_group_id uuid,
    p_event_id uuid,
    p_event_survey_id uuid,
    p_max_rows int,
    p_max_bytes bigint
)
returns json as $$
declare
    v_answers_bytes bigint;
    v_event_survey event_survey;
    v_responses_count bigint;
begin
    -- Load the survey of the group event
    select s.*
    into v_event_survey
    from event e
    join event_survey s on s.event_id = e.event_id
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false
    and s.event_survey_id = p_event_survey_id;

    -- Report nothing for missing or foreign surveys
    if not found then
        return null;
    end if;

    -- Measure the export before building it
    select
        coalesce(sum(octet_length(r.answers::text)), 0)::bigint,
        count(*)
    into v_answers_bytes, v_responses_count
    from event_survey_response r
    where r.event_survey_id = p_event_survey_id;

    -- Reject exports above either bound
    if v_responses_count > p_max_rows or v_answers_bytes > p_max_bytes then
        raise exception
            'survey export supports up to % responses and % bytes of answers; this survey has % responses and % bytes',
            p_max_rows,
            p_max_bytes,
            v_responses_count,
            v_answers_bytes
            using errcode = 'OCG01';
    end if;

    -- Export identified responses with their respondents
    if not v_event_survey.anonymous then
        return json_build_object(
            'anonymous', v_event_survey.anonymous,
            'questions', v_event_survey.questions,
            'responses', coalesce((
                select json_agg(
                    json_build_object(
                        'answers', r.answers,
                        'created_at', epoch_seconds(r.created_at),
                        'user', json_strip_nulls(json_build_object(
                            'username', u.username,

                            'company', u.company,
                            'name', u.name,
                            'title', u.title
                        )),

                        'updated_at', epoch_seconds(r.updated_at)
                    )
                    order by r.created_at, r.user_id
                )
                from event_survey_response r
                join "user" u on u.user_id = r.user_id
                where r.event_survey_id = p_event_survey_id
            ), '[]'::json),
            'title', v_event_survey.title
        );

    -- Export anonymous responses with dates and answers only
    else
        return json_build_object(
            'anonymous', v_event_survey.anonymous,
            'questions', v_event_survey.questions,
            'responses', coalesce((
                select json_agg(
                    json_build_object(
                        'answers', r.answers,
                        'created_at', epoch_seconds(r.created_at),

                        'updated_at', epoch_seconds(r.updated_at)
                    )
                    order by r.created_at, r.user_id
                )
                from event_survey_response r
                where r.event_survey_id = p_event_survey_id
            ), '[]'::json),
            'title', v_event_survey.title
        );
    end if;
end;
$$ language plpgsql stable;
