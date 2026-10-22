-- Returns the details of the response of a user to a survey: the submitted
-- answers, the respondent summary, how many survey questions it answers (a
-- non-blank text or at least one selected option), the ticket title of the
-- respondent's latest seat-holding purchase for the event and the last edit
-- date. No rows when the user has not answered the survey. Callers keep
-- respondents of anonymous surveys hidden.
create or replace function event_survey_response_details(
    p_event_survey_id uuid,
    p_user_id uuid
)
returns table (
    answered_questions_count int,
    answers jsonb,
    ticket_title text,
    updated_at timestamptz,
    user_summary jsonb
) as $$
    select
        (
            select count(*)::int
            from jsonb_array_elements(s.questions) as question(definition)
            where exists (
                select 1
                from questionnaire_answer_entries(r.answers) as answer(value)
                where answer.value->>'question_id' = question.definition->>'id'
                and questionnaire_answer_has_value(answer.value->'value')
            )
        ),
        r.answers,
        (
            select ep.ticket_title
            from event_purchase ep
            where ep.event_id = s.event_id
            and ep.user_id = r.user_id
            and event_purchase_holds_seat(ep.status)
            order by ep.created_at desc, ep.event_purchase_id desc
            limit 1
        ),
        r.updated_at,
        public_user_summary(u)
    from event_survey s
    join event_survey_response r on r.event_survey_id = s.event_survey_id
    join "user" u on u.user_id = r.user_id
    where s.event_survey_id = p_event_survey_id
    and r.user_id = p_user_id;
$$ language sql stable;
