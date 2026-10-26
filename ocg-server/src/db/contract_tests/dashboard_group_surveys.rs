//! Contract tests for the `DBDashboardGroup` event survey functions.

use std::collections::{HashMap, HashSet};

use anyhow::{Context, Result};
use chrono::{NaiveDate, TimeZone, Utc};
use tokio_postgres::types::Json;
use uuid::Uuid;

use crate::{
    db::{
        DBUnitOfWork, PgDB, PgExecutor,
        dashboard::{group::DBDashboardGroup, user::DBDashboardUser},
        user_facing_message,
    },
    types::{
        dashboard::group::surveys::{
            EventSurveyFull, EventSurveyInput, EventSurveyResponseNavigationFilters,
            EventSurveyResponsesFilters, EventSurveyStatusAction, EventSurveyStatusForm,
            EventSurveyTextAnswersFilters,
        },
        event_survey::{EventSurveyAudience, EventSurveyState},
        questionnaire::{
            QuestionnaireAnswer, QuestionnaireAnswerValue, QuestionnaireAnswers,
            QuestionnaireOption, QuestionnaireQuestion, QuestionnaireQuestionKind,
        },
    },
};

use super::helpers::*;

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_add_event_survey_creates_draft() -> Result<()> {
    // Setup a rolled-back unit of work and an input with local dates
    let uow = contract_unit_of_work().await?;
    let input = EventSurveyInput {
        closes_at: NaiveDate::from_ymd_opt(2099, 5, 20).and_then(|day| day.and_hms_opt(18, 30, 0)),
        description: Some("  Share your thoughts  ".to_string()),
        opens_at: NaiveDate::from_ymd_opt(2099, 5, 10).and_then(|day| day.and_hms_opt(9, 0, 0)),
        questions: vec![race_question()],
        ..identified_survey_input()
    };

    // Add the survey through the Rust database contract
    let event_survey_id = uow
        .add_event_survey(organizer_id(), subgroup_id(), survey_event_id(), &input)
        .await?;

    // Check the draft settings, with dates interpreted in the event timezone
    let survey = load_survey(&uow, survey_event_id(), event_survey_id).await?;
    assert!(!survey.summary.anonymous);
    assert_eq!(survey.summary.audience, EventSurveyAudience::Confirmed);
    assert_eq!(survey.summary.questions_count, 1);
    assert_eq!(survey.summary.revision, 1);
    assert_eq!(survey.summary.state, EventSurveyState::Draft);
    assert_eq!(survey.summary.title, "Contract identified survey");
    assert_eq!(
        survey.summary.closes_at,
        Utc.with_ymd_and_hms(2099, 5, 20, 16, 30, 0).single()
    );
    assert_eq!(
        survey.summary.effective_opens_at,
        Utc.with_ymd_and_hms(2099, 5, 10, 7, 0, 0).single()
    );
    assert_eq!(survey.description.as_deref(), Some("Share your thoughts"));
    assert_eq!(
        survey.opens_at,
        Utc.with_ymd_and_hms(2099, 5, 10, 7, 0, 0).single()
    );

    // Check the creation was audited
    let action: String = uow
        .fetch_scalar_one(
            "select action from audit_log where resource_id = $1::uuid",
            &[&event_survey_id],
        )
        .await?;
    assert_eq!(action, "event_survey_added");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_change_event_survey_status_applies_transitions() -> Result<()> {
    // Setup a rolled-back unit of work and the draft opening the editor shows
    let uow = contract_unit_of_work().await?;
    let draft = load_survey(
        &uow,
        survey_mark_ready_event_id(),
        survey_mark_ready_race_id(),
    )
    .await?;

    // Mark the draft ready with the opening time it showed
    uow.change_event_survey_status(
        organizer_id(),
        subgroup_id(),
        survey_mark_ready_event_id(),
        survey_mark_ready_race_id(),
        &EventSurveyStatusForm {
            action: EventSurveyStatusAction::MarkReady,
            revision: draft.summary.revision,

            expected_effective_opens_at: draft.summary.effective_opens_at,
        },
    )
    .await?;
    let ready = load_survey(
        &uow,
        survey_mark_ready_event_id(),
        survey_mark_ready_race_id(),
    )
    .await?;
    assert_eq!(ready.summary.revision, draft.summary.revision + 1);
    assert_eq!(ready.summary.state, EventSurveyState::Scheduled);

    // Move the scheduled survey back to draft
    uow.change_event_survey_status(
        organizer_id(),
        subgroup_id(),
        survey_mark_ready_event_id(),
        survey_mark_ready_race_id(),
        &status_form(EventSurveyStatusAction::BackToDraft, ready.summary.revision),
    )
    .await?;
    let draft_again = load_survey(
        &uow,
        survey_mark_ready_event_id(),
        survey_mark_ready_race_id(),
    )
    .await?;
    assert_eq!(draft_again.summary.state, EventSurveyState::Draft);

    // Close and reopen the open identified survey
    uow.change_event_survey_status(
        organizer_id(),
        subgroup_id(),
        survey_event_id(),
        survey_identified_id(),
        &status_form(EventSurveyStatusAction::Close, 2),
    )
    .await?;
    let closed = load_survey(&uow, survey_event_id(), survey_identified_id()).await?;
    assert!(closed.summary.closed_manually);
    assert!(closed.closed_at.is_some());
    assert_eq!(closed.summary.state, EventSurveyState::Closed);
    uow.change_event_survey_status(
        organizer_id(),
        subgroup_id(),
        survey_event_id(),
        survey_identified_id(),
        &status_form(EventSurveyStatusAction::Reopen, 3),
    )
    .await?;
    let reopened = load_survey(&uow, survey_event_id(), survey_identified_id()).await?;
    assert!(!reopened.summary.closed_manually);
    assert_eq!(reopened.summary.revision, 4);
    assert_eq!(reopened.summary.state, EventSurveyState::Open);

    // Check the status changes were audited
    let actions: Vec<String> = uow
        .client()
        .await?
        .query(
            "select action from audit_log where resource_id = any($1::uuid[]) order by action",
            &[&vec![survey_identified_id(), survey_mark_ready_race_id()]],
        )
        .await?
        .iter()
        .map(|row| row.get(0))
        .collect();
    assert_eq!(
        actions,
        vec![
            "event_survey_closed",
            "event_survey_marked_ready",
            "event_survey_moved_to_draft",
            "event_survey_reopened",
        ]
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_change_event_survey_status_rejects_mark_ready_racing_reschedule() -> Result<()>
{
    // Setup reschedule, status and probe connections
    let reschedule_uow = contract_unit_of_work().await?;
    let status_uow = contract_unit_of_work().await?;
    let probe_client = contract_tests_pool()?.get().await?;
    let reschedule_backend_pid = uow_backend_pid(&reschedule_uow).await?;
    let status_backend_pid = uow_backend_pid(&status_uow).await?;

    // Load the opening time the Mark ready confirmation shows
    let draft = load_survey(
        &status_uow,
        survey_mark_ready_event_id(),
        survey_mark_ready_race_id(),
    )
    .await?;

    // Reschedule the event while retaining its lock
    let payload = contract_event_input("Contract Survey Mark Ready Event", 10).to_db_payload()?;
    reschedule_uow
        .update_event(
            organizer_id(),
            subgroup_id(),
            survey_mark_ready_event_id(),
            &payload,
            &HashMap::new(),
            None,
        )
        .await?;

    // Confirm Mark ready with the opening time shown before the reschedule
    let status_change = tokio::spawn(async move {
        status_uow
            .change_event_survey_status(
                organizer_id(),
                subgroup_id(),
                survey_mark_ready_event_id(),
                survey_mark_ready_race_id(),
                &EventSurveyStatusForm {
                    action: EventSurveyStatusAction::MarkReady,
                    revision: draft.summary.revision,

                    expected_effective_opens_at: draft.summary.effective_opens_at,
                },
            )
            .await
    });
    wait_for_backend_blocker(&probe_client, reschedule_backend_pid, status_backend_pid).await?;

    // Commit the reschedule so the waiting confirmation observes it
    Box::new(reschedule_uow).commit().await?;
    let err = status_change
        .await?
        .expect_err("a confirmation of the old opening time should be rejected");

    // Check the survey stayed a draft
    assert_ocg01(
        &err,
        "the survey opening time changed; review and try again",
    );
    let status: String = probe_client
        .query_one(
            "select status from event_survey where event_survey_id = $1::uuid",
            &[&survey_mark_ready_race_id()],
        )
        .await?
        .get(0);
    assert_eq!(status, "draft");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_delete_event_survey_deletes_responses() -> Result<()> {
    // Setup a rolled-back unit of work
    let uow = contract_unit_of_work().await?;

    // Delete the answered identified survey
    uow.delete_event_survey(
        organizer_id(),
        subgroup_id(),
        survey_event_id(),
        survey_identified_id(),
    )
    .await?;

    // Check the survey and its responses are gone
    let survey = uow
        .get_event_survey(subgroup_id(), survey_event_id(), survey_identified_id())
        .await?;
    assert!(survey.is_none());
    let responses: i64 = uow
        .fetch_scalar_one(
            "select count(*) from event_survey_response where event_survey_id = $1::uuid",
            &[&survey_identified_id()],
        )
        .await?;
    assert_eq!(responses, 0);

    // Check the audit row keeps a snapshot without the responses
    let details: serde_json::Value = uow
        .fetch_scalar_one(
            "select details from audit_log where action = 'event_survey_deleted' and resource_id = $1::uuid",
            &[&survey_identified_id()],
        )
        .await?;
    assert_eq!(
        details,
        serde_json::json!({ "responses_count": 3, "title": "Contract identified survey" })
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_delete_event_survey_waits_for_concurrent_submission() -> Result<()> {
    // Setup submission, deletion and probe connections
    let submit_uow = contract_unit_of_work().await?;
    let delete_uow = contract_unit_of_work().await?;
    let probe_client = contract_tests_pool()?.get().await?;
    let submit_backend_pid = uow_backend_pid(&submit_uow).await?;
    let delete_backend_pid = uow_backend_pid(&delete_uow).await?;

    // Submit answers while retaining the event and survey locks
    submit_uow
        .submit_event_survey_response(
            survey_delete_after_submission_race_id(),
            survey_racer_id(),
            1,
            &race_answers("Before the deletion"),
        )
        .await?;

    // Delete the survey concurrently
    let deletion = tokio::spawn(async move {
        delete_uow
            .delete_event_survey(
                organizer_id(),
                subgroup_id(),
                survey_race_event_id(),
                survey_delete_after_submission_race_id(),
            )
            .await?;
        Ok::<_, anyhow::Error>(delete_uow)
    });
    wait_for_backend_blocker(&probe_client, submit_backend_pid, delete_backend_pid).await?;

    // Commit the submission so the waiting deletion observes it
    Box::new(submit_uow).commit().await?;
    let delete_uow = deletion.await??;

    // Check the deletion counted the committed response and removed it
    let details: serde_json::Value = delete_uow
        .fetch_scalar_one(
            "select details from audit_log where action = 'event_survey_deleted' and resource_id = $1::uuid",
            &[&survey_delete_after_submission_race_id()],
        )
        .await?;
    assert_eq!(
        details,
        serde_json::json!({
            "responses_count": 1,
            "title": "Contract delete after submission race survey"
        })
    );
    let responses: i64 = delete_uow
        .fetch_scalar_one(
            "select count(*) from event_survey_response where event_survey_id = $1::uuid",
            &[&survey_delete_after_submission_race_id()],
        )
        .await?;
    assert_eq!(responses, 0);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_analytics_deserializes_survey_summary() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load the analytics of the survey event
    let stats = db
        .get_event_analytics(subgroup_id(), survey_event_id())
        .await?
        .context("survey event analytics should be returned")?;

    // Check the rows cover the surveys that are not drafts, in creation order
    let surveys = &stats.surveys.surveys;
    assert_eq!(surveys.len(), 2);
    assert_eq!(surveys[0].eligible_count, 3);
    assert_eq!(surveys[0].eligible_respondents_count, 2);
    assert_eq!(surveys[0].event_survey_id, survey_identified_id());
    assert_eq!(surveys[0].responses_count, 3);
    assert_eq!(surveys[0].state, EventSurveyState::Open);
    assert_eq!(surveys[0].title, "Contract identified survey");
    assert_eq!(surveys[1].eligible_count, 2);
    assert_eq!(surveys[1].event_survey_id, survey_anonymous_id());

    // Check the totals behind the weighted response rate
    assert_eq!(stats.surveys.total_eligible_count, 5);
    assert_eq!(stats.surveys.total_eligible_respondents_count, 4);
    assert_eq!(stats.surveys.response_rate(), Some(0.8));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_survey_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load the identified survey through the Rust database contract
    let survey = db
        .get_event_survey(subgroup_id(), survey_event_id(), survey_identified_id())
        .await?
        .context("identified survey should be returned")?;

    // Check the editor fields and the shared summary
    assert_eq!(
        survey.created_at,
        Utc.with_ymd_and_hms(2025, 3, 28, 10, 0, 0).unwrap()
    );
    assert_eq!(survey.questions.len(), 3);
    assert_eq!(survey.questions[0].id, survey_free_text_question_id());
    assert_eq!(
        survey.questions[0].kind,
        QuestionnaireQuestionKind::FreeText
    );
    assert_eq!(survey.questions[1].options.len(), 2);
    assert_eq!(survey.summary.event_survey_id, survey_identified_id());
    assert_eq!(survey.summary.revision, 2);
    assert!(survey.closed_at.is_none());
    assert_eq!(
        survey.description.as_deref(),
        Some("Tell us how the contract event went")
    );
    assert!(survey.opens_at.is_none());
    assert_eq!(
        survey.updated_at,
        Utc.with_ymd_and_hms(2025, 3, 29, 10, 0, 0).single()
    );

    // Check surveys of foreign groups are not returned
    let foreign = db
        .get_event_survey(group_id(), survey_event_id(), survey_identified_id())
        .await?;
    assert!(foreign.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_survey_export_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Export the identified survey
    let identified = db
        .get_event_survey_export(
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            10,
            1_000_000,
        )
        .await?
        .context("identified export should be returned")?;

    // Check the identified export carries respondent details
    assert!(!identified.anonymous);
    assert_eq!(identified.questions.len(), 3);
    assert_eq!(identified.responses.len(), 3);
    assert_eq!(identified.title, "Contract identified survey");
    let first = &identified.responses[0];
    assert_eq!(first.answers.answers.len(), 3);
    assert_eq!(
        first.created_at,
        Utc.with_ymd_and_hms(2025, 4, 2, 9, 0, 0).unwrap()
    );
    assert_eq!(
        first.updated_at,
        Utc.with_ymd_and_hms(2025, 4, 3, 9, 0, 0).single()
    );
    let respondent = first.user.as_ref().context("respondent should be exported")?;
    assert_eq!(respondent.username, "survey-respondent");
    assert_eq!(respondent.company.as_deref(), Some("Contract Survey Corp"));
    assert_eq!(
        respondent.name.as_deref(),
        Some("Contract Survey Respondent")
    );
    assert_eq!(respondent.title.as_deref(), Some("Platform Engineer"));
    let second = identified.responses[1]
        .user
        .as_ref()
        .context("second respondent should be exported")?;
    assert_eq!(second.username, "survey-second-respondent");
    assert!(second.company.is_none());
    assert!(second.title.is_none());
    let former = identified.responses[2]
        .user
        .as_ref()
        .context("former attendee should be exported")?;
    assert_eq!(former.username, "survey-former-attendee");

    // Export the anonymous survey
    let anonymous = db
        .get_event_survey_export(
            subgroup_id(),
            survey_event_id(),
            survey_anonymous_id(),
            10,
            1_000_000,
        )
        .await?
        .context("anonymous export should be returned")?;

    // Check the anonymous export carries dates and answers only
    assert!(anonymous.anonymous);
    assert_eq!(anonymous.responses.len(), 2);
    assert!(anonymous.responses.iter().all(|response| response.user.is_none()));
    assert!(anonymous.responses[0].updated_at.is_none());

    // Check surveys of foreign groups are not exported
    let foreign = db
        .get_event_survey_export(
            group_id(),
            survey_event_id(),
            survey_identified_id(),
            10,
            1_000_000,
        )
        .await?;
    assert!(foreign.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_survey_export_rejects_oversized_export() -> Result<()> {
    // Setup the contract database and the measured answers of the identified survey
    let db = contract_tests_db()?;
    let client = contract_tests_pool()?.get().await?;
    let answers_bytes: i64 = client
        .query_one(
            "select sum(octet_length(answers::text))::bigint from event_survey_response where event_survey_id = $1::uuid",
            &[&survey_identified_id()],
        )
        .await?
        .get(0);

    // Check exports above the row bound are rejected with both bounds and sizes
    let err = db
        .get_event_survey_export(
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            2,
            1_000_000,
        )
        .await
        .expect_err("export above the row bound should be rejected");
    assert_ocg01(
        &err,
        &format!(
            "survey export supports up to 2 responses and 1000000 bytes of answers; this survey has 3 responses and {answers_bytes} bytes"
        ),
    );

    // Check exports above the byte bound are rejected with both bounds and sizes
    let max_bytes = usize::try_from(answers_bytes - 1)?;
    let err = db
        .get_event_survey_export(
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            100,
            max_bytes,
        )
        .await
        .expect_err("export above the byte bound should be rejected");
    assert_ocg01(
        &err,
        &format!(
            "survey export supports up to 100 responses and {max_bytes} bytes of answers; this survey has 3 responses and {answers_bytes} bytes"
        ),
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_survey_export_stays_consistent_while_responses_grow() -> Result<()>
{
    // Setup the exporting database, an independent writer, and the size bounds
    let db = contract_tests_db()?;
    let writer_db = contract_tests_db()?;
    let client = contract_tests_pool()?.get().await?;
    let answers = race_answers("Export growth answer");
    let answer_bytes: i32 = client
        .query_one("select octet_length($1::jsonb::text)", &[&Json(&answers)])
        .await?
        .get(0);
    let answer_bytes = usize::try_from(answer_bytes)?;
    let rows_bound = SurveyExportBounds {
        max_bytes: 1_000_000,
        max_rows: 6,
    };
    let bytes_bound = SurveyExportBounds {
        max_bytes: answer_bytes * 6,
        max_rows: 1_000,
    };

    // Check the export of the survey before any response
    let initial = check_survey_export_snapshot(&db, &rows_bound, answer_bytes).await?;
    assert_eq!(initial, Some(0));

    // Commit one response per export respondent from the writer connection
    let writer = tokio::spawn(async move {
        for n in 1..=SURVEY_EXPORT_RESPONDENTS {
            writer_db
                .submit_event_survey_response(
                    survey_export_growth_id(),
                    survey_export_respondent_id(n),
                    1,
                    &race_answers("Export growth answer"),
                )
                .await?;
        }
        Ok::<(), anyhow::Error>(())
    });

    // Export repeatedly while responses grow, alternating the binding bound
    let mut use_bytes_bound = false;
    while !writer.is_finished() {
        let bounds = if use_bytes_bound {
            &bytes_bound
        } else {
            &rows_bound
        };
        check_survey_export_snapshot(&db, bounds, answer_bytes).await?;
        use_bytes_bound = !use_bytes_bound;
    }
    writer.await??;

    // Check the final export is rejected by both bounds and fits a larger one
    assert_eq!(
        check_survey_export_snapshot(&db, &rows_bound, answer_bytes).await?,
        None
    );
    assert_eq!(
        check_survey_export_snapshot(&db, &bytes_bound, answer_bytes).await?,
        None
    );
    let full_bounds = SurveyExportBounds {
        max_bytes: 1_000_000,
        max_rows: usize::from(SURVEY_EXPORT_RESPONDENTS),
    };
    assert_eq!(
        check_survey_export_snapshot(&db, &full_bounds, answer_bytes).await?,
        Some(usize::from(SURVEY_EXPORT_RESPONDENTS))
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_survey_response_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;
    let second_respondent_id = survey_second_respondent_id();

    // Load the second response among all respondents
    let response = db
        .get_event_survey_response(
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            second_respondent_id,
            &EventSurveyResponseNavigationFilters::default(),
        )
        .await?
        .context("the response should be returned")?;

    // Check the answers, respondent details and navigation
    assert_eq!(response.answers.answers.len(), 3);
    assert_eq!(response.position, 2);
    assert_eq!(response.summary.answered_questions_count, 2);
    assert_eq!(
        response.summary.created_at,
        Utc.with_ymd_and_hms(2025, 4, 2, 11, 0, 0).unwrap()
    );
    assert_eq!(response.summary.user.user_id, second_respondent_id);
    assert!(response.summary.ticket_title.is_none());
    assert!(response.summary.updated_at.is_none());
    assert_eq!(response.total, 3);
    assert_eq!(response.next_user_id, Some(survey_former_attendee_id()));
    assert_eq!(response.previous_user_id, Some(survey_respondent_id()));

    // Load the same response among the respondents matching a search
    let searched = db
        .get_event_survey_response(
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            second_respondent_id,
            &EventSurveyResponseNavigationFilters {
                ts_query: Some("respondent".to_string()),
            },
        )
        .await?
        .context("the response should be returned")?;

    // Check the navigation stays within the matching respondents
    assert_eq!(searched.position, 2);
    assert_eq!(searched.total, 2);
    assert!(searched.next_user_id.is_none());
    assert_eq!(searched.previous_user_id, Some(survey_respondent_id()));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_survey_results_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load the identified survey results
    let results = db
        .get_event_survey_results(subgroup_id(), survey_event_id(), survey_identified_id())
        .await?
        .context("results should be returned")?;

    // Check the free-text question carries its first answers
    assert_eq!(results.questions.len(), 3);
    let free_text = &results.questions[0];
    assert_eq!(free_text.kind, QuestionnaireQuestionKind::FreeText);
    assert_eq!(free_text.position, 1);
    assert_eq!(free_text.prompt, "What should we improve?");
    assert_eq!(free_text.question_id, survey_free_text_question_id());
    assert!(!free_text.required);
    assert!(free_text.breakdown.is_none());
    let text_answers = free_text
        .text_answers
        .as_ref()
        .context("free-text questions should carry answers")?;
    assert_eq!(
        text_answers.answers,
        vec![
            "More hands-on time".to_string(),
            "Shorter breaks".to_string()
        ]
    );
    assert_eq!(text_answers.total, 2);

    // Check the select questions carry their breakdowns
    let single = &results.questions[1];
    assert_eq!(single.kind, QuestionnaireQuestionKind::SingleSelect);
    assert_eq!(single.position, 2);
    assert_eq!(single.question_id, survey_single_select_question_id());
    assert!(single.required);
    assert!(single.text_answers.is_none());
    let single_breakdown = single
        .breakdown
        .as_ref()
        .context("select questions should carry a breakdown")?;
    assert_eq!(
        single_breakdown
            .options
            .iter()
            .map(|option| (option.label.as_str(), option.count))
            .collect::<Vec<_>>(),
        vec![("Good", 2), ("Poor", 1)]
    );
    assert_eq!(single_breakdown.respondents, 3);
    let multi = &results.questions[2];
    assert_eq!(multi.kind, QuestionnaireQuestionKind::MultiSelect);
    assert!(multi.text_answers.is_none());
    let multi_breakdown = multi
        .breakdown
        .as_ref()
        .context("select questions should carry a breakdown")?;
    assert_eq!(multi_breakdown.respondents, 2);
    assert_eq!(multi_breakdown.selections, 3);

    // Check the summary
    assert_eq!(results.survey.event_survey_id, survey_identified_id());
    assert_eq!(results.survey.eligible_respondents_count, 2);
    assert_eq!(results.survey.responses_count, 3);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_survey_responses_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // List the first respondent of the identified survey
    let first_page = db
        .list_event_survey_responses(
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            &EventSurveyResponsesFilters {
                limit: Some(1),
                offset: Some(0),
                ts_query: None,
            },
        )
        .await?
        .context("responses should be returned")?;

    // Check the respondent with a ticket and an edited response
    assert_eq!(first_page.responses.len(), 1);
    assert_eq!(first_page.total, 3);
    let first = &first_page.responses[0];
    assert_eq!(first.answered_questions_count, 3);
    assert_eq!(
        first.created_at,
        Utc.with_ymd_and_hms(2025, 4, 2, 9, 0, 0).unwrap()
    );
    assert_eq!(first.user.user_id, survey_respondent_id());
    assert_eq!(first.user.company.as_deref(), Some("Contract Survey Corp"));
    assert_eq!(first.user.title.as_deref(), Some("Platform Engineer"));
    assert_eq!(first.ticket_title.as_deref(), Some("General Admission"));
    assert_eq!(
        first.updated_at,
        Some(Utc.with_ymd_and_hms(2025, 4, 3, 9, 0, 0).unwrap())
    );

    // List the second respondent of the identified survey
    let second_page = db
        .list_event_survey_responses(
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            &EventSurveyResponsesFilters {
                limit: Some(1),
                offset: Some(1),
                ts_query: None,
            },
        )
        .await?
        .context("responses should be returned")?;

    // Check the respondent without a ticket whose blank text is unanswered
    let second = &second_page.responses[0];
    assert_eq!(second.answered_questions_count, 2);
    assert_eq!(second.user.user_id, survey_second_respondent_id());
    assert_eq!(second.user.username, "survey-second-respondent");
    assert_eq!(
        second.user.name.as_deref(),
        Some("Contract Survey Second Respondent")
    );
    assert!(second.ticket_title.is_none());
    assert!(second.updated_at.is_none());

    // Check the search narrows the respondents and their total
    let search_page = db
        .list_event_survey_responses(
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            &EventSurveyResponsesFilters {
                limit: Some(10),
                offset: Some(0),
                ts_query: Some("former".to_string()),
            },
        )
        .await?
        .context("responses should be returned")?;
    assert_eq!(search_page.total, 1);
    assert_eq!(
        search_page.responses[0].user.user_id,
        survey_former_attendee_id()
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_survey_text_answers_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // List the answers to the free-text question
    let page = db
        .list_event_survey_text_answers(
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            survey_free_text_question_id(),
            &EventSurveyTextAnswersFilters::default(),
        )
        .await?
        .context("answers should be returned")?;

    // Check the page of plain answers skips the blank answer
    assert_eq!(
        page.answers,
        vec![
            "More hands-on time".to_string(),
            "Shorter breaks".to_string()
        ]
    );
    assert_eq!(page.position, 1);
    assert_eq!(page.prompt, "What should we improve?");
    assert_eq!(page.total, 2);

    // Check the search keeps the matching answers only
    let search = db
        .list_event_survey_text_answers(
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            survey_free_text_question_id(),
            &EventSurveyTextAnswersFilters {
                ts_query: Some("BREAKS".to_string()),
                ..EventSurveyTextAnswersFilters::default()
            },
        )
        .await?
        .context("matching answers should be returned")?;
    assert_eq!(search.answers, vec!["Shorter breaks".to_string()]);
    assert_eq!(search.total, 1);

    // Check select questions have no text answers page
    let select = db
        .list_event_survey_text_answers(
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            survey_single_select_question_id(),
            &EventSurveyTextAnswersFilters::default(),
        )
        .await?;
    assert!(select.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_surveys_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // List the surveys of the survey event
    let surveys = db.list_event_surveys(subgroup_id(), survey_event_id()).await?;

    // Check the rows are ordered by creation
    assert_eq!(
        surveys
            .iter()
            .map(|survey| survey.event_survey_id)
            .collect::<Vec<_>>(),
        vec![
            survey_identified_id(),
            survey_anonymous_id(),
            survey_draft_id()
        ]
    );

    // Check the complete summary of the identified survey
    let identified = &surveys[0];
    assert!(!identified.anonymous);
    assert!(!identified.anonymous_locked);
    assert_eq!(identified.audience, EventSurveyAudience::Confirmed);
    assert!(!identified.closed_manually);
    assert_eq!(identified.eligible_count, 3);
    assert_eq!(identified.eligible_respondents_count, 2);
    assert!(identified.locked);
    assert_eq!(identified.questions_count, 3);
    assert_eq!(identified.responses_count, 3);
    assert_eq!(identified.revision, 2);
    assert_eq!(identified.state, EventSurveyState::Open);
    assert_eq!(identified.title, "Contract identified survey");
    assert_eq!(
        identified.closes_at,
        Utc.with_ymd_and_hms(2099, 1, 1, 0, 0, 0).single()
    );
    assert_eq!(
        identified.effective_opens_at,
        Utc.with_ymd_and_hms(2025, 4, 1, 19, 0, 0).single()
    );
    assert!(identified.open_notification_processed_at.is_none());

    // Check the anonymous and draft surveys
    let anonymous = &surveys[1];
    assert!(anonymous.anonymous_locked);
    assert_eq!(anonymous.audience, EventSurveyAudience::CheckedIn);
    assert_eq!(anonymous.eligible_count, 2);
    assert_eq!(
        anonymous.open_notification_processed_at,
        Utc.with_ymd_and_hms(2025, 4, 2, 9, 5, 0).single()
    );
    let draft = &surveys[2];
    assert!(!draft.anonymous_locked);
    assert!(!draft.locked);
    assert_eq!(draft.questions_count, 0);
    assert_eq!(draft.state, EventSurveyState::Draft);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_submit_event_survey_response_locks_settings_against_anonymity_change()
-> Result<()> {
    // Setup submission, update and probe connections
    let submit_uow = contract_unit_of_work().await?;
    let update_uow = contract_unit_of_work().await?;
    let probe_client = contract_tests_pool()?.get().await?;
    let submit_backend_pid = uow_backend_pid(&submit_uow).await?;
    let update_backend_pid = uow_backend_pid(&update_uow).await?;

    // Submit the first response while retaining the event and survey locks
    submit_uow
        .submit_event_survey_response(
            survey_first_response_race_id(),
            survey_racer_id(),
            1,
            &race_answers("First"),
        )
        .await?;

    // Make the survey anonymous from the dashboard concurrently
    let update = tokio::spawn(async move {
        update_uow
            .update_event_survey(
                organizer_id(),
                subgroup_id(),
                survey_race_event_id(),
                survey_first_response_race_id(),
                1,
                &race_survey_input(true, "Contract first response race survey"),
            )
            .await
    });
    wait_for_backend_blocker(&probe_client, submit_backend_pid, update_backend_pid).await?;

    // Commit the response so the waiting update observes it
    Box::new(submit_uow).commit().await?;
    let err = update
        .await?
        .expect_err("answered surveys should keep their anonymity");

    // Check the response locked the settings it was given under
    assert_ocg01(
        &err,
        "survey questions, audience and anonymity cannot change once it has responses",
    );
    let row = probe_client
        .query_one(
            "select anonymous, first_response_at is not null from event_survey where event_survey_id = $1::uuid",
            &[&survey_first_response_race_id()],
        )
        .await?;
    assert!(!row.get::<_, bool>(0));
    assert!(row.get::<_, bool>(1));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_submit_event_survey_response_rejects_concurrent_reconfiguration() -> Result<()>
{
    // Setup update, submission and probe connections
    let update_uow = contract_unit_of_work().await?;
    let submit_uow = contract_unit_of_work().await?;
    let probe_client = contract_tests_pool()?.get().await?;
    let update_backend_pid = uow_backend_pid(&update_uow).await?;
    let submit_backend_pid = uow_backend_pid(&submit_uow).await?;

    // Make the survey anonymous while retaining the event and survey locks
    update_uow
        .update_event_survey(
            organizer_id(),
            subgroup_id(),
            survey_race_event_id(),
            survey_stale_race_id(),
            1,
            &race_survey_input(true, "Contract stale submission race survey"),
        )
        .await?;

    // Submit answers given to the previous revision concurrently
    let submission = tokio::spawn(async move {
        submit_uow
            .submit_event_survey_response(
                survey_stale_race_id(),
                survey_racer_id(),
                1,
                &race_answers("Stale"),
            )
            .await
    });
    wait_for_backend_blocker(&probe_client, update_backend_pid, submit_backend_pid).await?;

    // Commit the update so the waiting submission observes the new revision
    Box::new(update_uow).commit().await?;
    let err = submission
        .await?
        .expect_err("answers to an older revision should be rejected");

    // Check no response was stored
    assert_ocg01(&err, "the survey changed; review and try again");
    assert_survey_has_no_responses(&probe_client, survey_stale_race_id()).await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_submit_event_survey_response_rejects_concurrently_closed_survey() -> Result<()>
{
    // Setup close, submission and probe connections
    let close_uow = contract_unit_of_work().await?;
    let submit_uow = contract_unit_of_work().await?;
    let probe_client = contract_tests_pool()?.get().await?;
    let close_backend_pid = uow_backend_pid(&close_uow).await?;
    let submit_backend_pid = uow_backend_pid(&submit_uow).await?;

    // Close the survey while retaining the event and survey locks
    close_uow
        .change_event_survey_status(
            organizer_id(),
            subgroup_id(),
            survey_race_event_id(),
            survey_close_race_id(),
            &status_form(EventSurveyStatusAction::Close, 1),
        )
        .await?;

    // Submit answers concurrently
    let submission = tokio::spawn(async move {
        submit_uow
            .submit_event_survey_response(
                survey_close_race_id(),
                survey_racer_id(),
                1,
                &race_answers("Late"),
            )
            .await
    });
    wait_for_backend_blocker(&probe_client, close_backend_pid, submit_backend_pid).await?;

    // Commit the close so the waiting submission observes it
    Box::new(close_uow).commit().await?;
    let err = submission
        .await?
        .expect_err("answers to a closed survey should be rejected");

    // Check no response was stored
    assert_ocg01(&err, "event survey is not open");
    assert_survey_has_no_responses(&probe_client, survey_close_race_id()).await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_submit_event_survey_response_rejects_concurrently_deleted_survey()
-> Result<()> {
    // Setup delete, submission and probe connections
    let delete_uow = contract_unit_of_work().await?;
    let submit_uow = contract_unit_of_work().await?;
    let probe_client = contract_tests_pool()?.get().await?;
    let delete_backend_pid = uow_backend_pid(&delete_uow).await?;
    let submit_backend_pid = uow_backend_pid(&submit_uow).await?;

    // Delete the survey while retaining the event lock
    delete_uow
        .delete_event_survey(
            organizer_id(),
            subgroup_id(),
            survey_race_event_id(),
            survey_delete_race_id(),
        )
        .await?;

    // Submit answers concurrently
    let submission = tokio::spawn(async move {
        submit_uow
            .submit_event_survey_response(
                survey_delete_race_id(),
                survey_racer_id(),
                1,
                &race_answers("Orphan"),
            )
            .await
    });
    wait_for_backend_blocker(&probe_client, delete_backend_pid, submit_backend_pid).await?;

    // Commit the deletion so the waiting submission observes it
    Box::new(delete_uow).commit().await?;
    let err = submission
        .await?
        .expect_err("answers to a deleted survey should be rejected");

    // Check no response was stored
    assert_ocg01(&err, "event survey not found");
    assert_survey_has_no_responses(&probe_client, survey_delete_race_id()).await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_update_event_survey_bumps_revision_for_configuration_changes() -> Result<()> {
    // Setup a rolled-back unit of work and a configuration for the draft
    let uow = contract_unit_of_work().await?;
    let input = EventSurveyInput {
        anonymous: true,
        closes_at: NaiveDate::from_ymd_opt(2099, 1, 15).and_then(|day| day.and_hms_opt(12, 0, 0)),
        questions: vec![race_question()],
        title: "Contract draft survey".to_string(),
        ..identified_survey_input()
    };

    // Configure the draft survey
    uow.update_event_survey(
        organizer_id(),
        subgroup_id(),
        survey_event_id(),
        survey_draft_id(),
        1,
        &input,
    )
    .await?;

    // Check the configuration change increased the revision
    let survey = load_survey(&uow, survey_event_id(), survey_draft_id()).await?;
    assert_eq!(survey.summary.questions_count, 1);
    assert_eq!(survey.summary.revision, 2);
    assert_eq!(
        survey.summary.closes_at,
        Utc.with_ymd_and_hms(2099, 1, 15, 11, 0, 0).single()
    );
    assert!(survey.updated_at.is_some());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_update_event_survey_keeps_locked_settings() -> Result<()> {
    // Setup a rolled-back unit of work and the editor input of the answered survey
    let uow = contract_unit_of_work().await?;
    let survey = load_survey(&uow, survey_event_id(), survey_identified_id()).await?;
    let input = EventSurveyInput {
        description: Some("Contract renamed introduction".to_string()),
        questions: survey.questions,
        title: "Contract renamed survey".to_string(),
        ..identified_survey_input()
    };

    // Rename the answered survey, echoing its dates in the event timezone
    uow.update_event_survey(
        organizer_id(),
        subgroup_id(),
        survey_event_id(),
        survey_identified_id(),
        2,
        &input,
    )
    .await?;

    // Check the rename kept the revision and both stored dates
    let renamed = load_survey(&uow, survey_event_id(), survey_identified_id()).await?;
    assert_eq!(renamed.summary.revision, 2);
    assert_eq!(renamed.summary.title, "Contract renamed survey");
    assert_eq!(
        renamed.description.as_deref(),
        Some("Contract renamed introduction")
    );
    assert_eq!(renamed.summary.closes_at, survey.summary.closes_at);
    assert_eq!(renamed.opens_at, survey.opens_at);

    // Check the anonymity of the answered survey is locked
    uow.execute("savepoint locked_settings", &[]).await?;
    let err = uow
        .update_event_survey(
            organizer_id(),
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            2,
            &EventSurveyInput {
                anonymous: true,
                ..input.clone()
            },
        )
        .await
        .expect_err("answered surveys should keep their anonymity");
    assert_ocg01(
        &err,
        "survey questions, audience and anonymity cannot change once it has responses",
    );
    uow.execute("rollback to savepoint locked_settings", &[]).await?;

    // Check edits from a stale form are rejected
    let err = uow
        .update_event_survey(
            organizer_id(),
            subgroup_id(),
            survey_event_id(),
            survey_identified_id(),
            1,
            &input,
        )
        .await
        .expect_err("stale forms should be rejected");
    assert_ocg01(&err, "the survey changed; review and try again");

    Ok(())
}

// Helpers.

/// Size bounds of one survey export request.
struct SurveyExportBounds {
    /// Maximum bytes of stored answers.
    max_bytes: usize,
    /// Maximum number of responses.
    max_rows: usize,
}

/// Exports the export growth survey and checks the payload agrees with its own
/// size check. Returns the number of exported responses, or `None` when the
/// export was rejected for a measured size above the bounds.
async fn check_survey_export_snapshot(
    db: &PgDB,
    bounds: &SurveyExportBounds,
    answer_bytes: usize,
) -> Result<Option<usize>> {
    let result = db
        .get_event_survey_export(
            subgroup_id(),
            survey_race_event_id(),
            survey_export_growth_id(),
            bounds.max_rows,
            bounds.max_bytes,
        )
        .await;

    match result {
        // Accepted exports fit the bounds with distinct respondents, oldest first
        Ok(export) => {
            let export = export.context("export growth survey should exist")?;
            let count = export.responses.len();
            assert!(count <= bounds.max_rows, "{count} rows exported");
            assert!(
                count * answer_bytes <= bounds.max_bytes,
                "{count} rows exported"
            );
            assert!(
                export
                    .responses
                    .windows(2)
                    .all(|pair| pair[0].created_at <= pair[1].created_at)
            );
            let respondents = export
                .responses
                .iter()
                .filter_map(|response| response.user.as_ref().map(|user| user.username.clone()))
                .collect::<HashSet<_>>();
            assert_eq!(respondents.len(), count);
            Ok(Some(count))
        }
        // Rejected exports measured one snapshot above the bounds
        Err(err) => {
            let message = user_facing_message(&err)
                .with_context(|| format!("export should only fail by size: {err:#}"))?;
            let measured = message
                .split("this survey has ")
                .nth(1)
                .context("export rejection should report the measured size")?
                .split_whitespace()
                .collect::<Vec<_>>();
            let [count, "responses", "and", bytes, "bytes"] = measured.as_slice() else {
                anyhow::bail!("unexpected export rejection: {message}");
            };
            let count: usize = count.parse()?;
            let bytes: usize = bytes.parse()?;
            assert!(
                count > bounds.max_rows || bytes > bounds.max_bytes,
                "{message}"
            );
            assert_eq!(bytes, count * answer_bytes, "{message}");
            Ok(None)
        }
    }
}

/// Checks that a concurrency contract survey stored no response.
async fn assert_survey_has_no_responses(
    client: &tokio_postgres::Client,
    event_survey_id: Uuid,
) -> Result<()> {
    let responses: i64 = client
        .query_one(
            "select count(*) from event_survey_response where event_survey_id = $1::uuid",
            &[&event_survey_id],
        )
        .await?
        .get(0);
    assert_eq!(responses, 0);

    Ok(())
}

/// Loads a survey of the given subgroup event, failing when it is missing.
async fn load_survey(
    db: &(impl DBDashboardGroup + Sync),
    event_id: Uuid,
    event_survey_id: Uuid,
) -> Result<EventSurveyFull> {
    db.get_event_survey(subgroup_id(), event_id, event_survey_id)
        .await?
        .context("survey should be returned")
}

/// Builds the editor input that echoes the identified survey settings.
fn identified_survey_input() -> EventSurveyInput {
    EventSurveyInput {
        anonymous: false,
        audience: EventSurveyAudience::Confirmed,
        title: "Contract identified survey".to_string(),

        closes_at: NaiveDate::from_ymd_opt(2099, 1, 1).and_then(|day| day.and_hms_opt(1, 0, 0)),
        description: Some("Tell us how the contract event went".to_string()),
        opens_at: None,
        questions: vec![],
        revision: None,
    }
}

/// Builds an answer to the free-text question of the concurrency surveys.
fn race_answers(value: &str) -> QuestionnaireAnswers {
    QuestionnaireAnswers {
        answers: vec![QuestionnaireAnswer {
            question_id: survey_race_question_id(),
            value: QuestionnaireAnswerValue::One(value.to_string()),
        }],
    }
}

/// Builds the free-text question of the concurrency surveys.
fn race_question() -> QuestionnaireQuestion {
    QuestionnaireQuestion {
        id: survey_race_question_id(),
        kind: QuestionnaireQuestionKind::FreeText,
        prompt: "Any feedback?".to_string(),
        required: false,

        options: Vec::<QuestionnaireOption>::new(),
    }
}

/// Builds the editor input of a concurrency survey with the given anonymity.
fn race_survey_input(anonymous: bool, title: &str) -> EventSurveyInput {
    EventSurveyInput {
        anonymous,
        audience: EventSurveyAudience::Confirmed,
        title: title.to_string(),

        closes_at: NaiveDate::from_ymd_opt(2099, 1, 1).and_then(|day| day.and_hms_opt(0, 0, 0)),
        description: None,
        opens_at: None,
        questions: vec![race_question()],
        revision: None,
    }
}

/// Builds a status change without an expected opening time.
fn status_form(action: EventSurveyStatusAction, revision: i64) -> EventSurveyStatusForm {
    EventSurveyStatusForm {
        action,
        revision,

        expected_effective_opens_at: None,
    }
}
