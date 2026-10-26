//! Reusable questionnaire definitions and answer payloads.

#![allow(clippy::trivially_copy_pass_by_ref)]
#![allow(clippy::ref_option)]

use std::collections::HashSet;

use garde::Validate;
use serde::{Deserialize, Deserializer, Serialize, de::Error as DeError};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::validation::{
    MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_ENTITY_NAME, MAX_LEN_QUESTIONNAIRE_ANSWER, trimmed_non_empty,
};

/// One attendee answer keyed by question identifier.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestionnaireAnswer {
    /// Question identifier this answer belongs to.
    pub question_id: Uuid,
    /// Answer value.
    pub value: QuestionnaireAnswerValue,
}

/// Answer value for a questionnaire question.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum QuestionnaireAnswerValue {
    /// Selected option identifiers for multi-select questions.
    Many(Vec<Uuid>),
    /// Free-text answer or selected option identifier.
    One(String),
}

/// Full answer payload submitted by an attendee.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct QuestionnaireAnswers {
    /// Answers keyed by question identifier.
    #[serde(default)]
    pub answers: Vec<QuestionnaireAnswer>,
}

impl QuestionnaireAnswers {
    /// Returns the answer value submitted for one question.
    pub fn get(&self, question_id: Uuid) -> Option<&QuestionnaireAnswerValue> {
        self.answers
            .iter()
            .find(|answer| answer.question_id == question_id)
            .map(|answer| &answer.value)
    }

    /// Validates answers against the configured questions.
    pub fn validate_against_questions(
        &self,
        questions: &[QuestionnaireQuestion],
    ) -> Result<(), String> {
        self.validate_payload().map_err(|err| err.to_string())?;

        if questions.is_empty() {
            if self.answers.is_empty() {
                return Ok(());
            }

            return Err(
                "questionnaire answers cannot be submitted when questions are not configured"
                    .to_string(),
            );
        }

        for answer in &self.answers {
            if !questions.iter().any(|question| question.id == answer.question_id) {
                return Err("questionnaire answer references an unknown question".to_string());
            }
        }

        for question in questions {
            question.validate_answer(self)?;
        }

        Ok(())
    }

    /// Validates answer structure that does not require question definitions.
    pub fn validate_payload(&self) -> garde::Result {
        let mut question_ids = HashSet::new();
        for answer in &self.answers {
            // Reject several answers for the same question
            if !question_ids.insert(answer.question_id) {
                return Err(garde::Error::new(
                    "questionnaire answers must include each question at most once",
                ));
            }

            match &answer.value {
                // Reject repeated options in multi-select answers
                QuestionnaireAnswerValue::Many(option_ids) => {
                    let mut selected_option_ids = HashSet::new();
                    for option_id in option_ids {
                        if !selected_option_ids.insert(option_id) {
                            return Err(garde::Error::new(
                                "multi-select questionnaire answers cannot repeat options",
                            ));
                        }
                    }
                }
                // Reject text values above the free-text answer limit
                QuestionnaireAnswerValue::One(value) => {
                    if value.chars().count() > MAX_LEN_QUESTIONNAIRE_ANSWER {
                        return Err(garde::Error::new(
                            "free-text questionnaire answer is too long",
                        ));
                    }
                }
            }
        }

        Ok(())
    }
}

/// One selectable option for a questionnaire question.
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub struct QuestionnaireOption {
    /// Option identifier.
    #[garde(skip)]
    pub id: Uuid,
    /// Option label.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub label: String,
}

/// Selections of one questionnaire question option.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct QuestionnaireOptionCount {
    /// Selections.
    pub count: i64,
    /// Option label.
    pub label: String,
    /// Option identifier.
    pub option_id: Uuid,
}

/// One reusable questionnaire question definition.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub struct QuestionnaireQuestion {
    /// Question identifier.
    #[garde(skip)]
    pub id: Uuid,
    /// Question type.
    #[garde(skip)]
    pub kind: QuestionnaireQuestionKind,
    /// Question prompt shown to attendees.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub prompt: String,
    /// Whether attendees must answer this question.
    #[garde(skip)]
    pub required: bool,

    /// Selectable options for select-style questions.
    #[serde(default)]
    #[garde(dive)]
    pub options: Vec<QuestionnaireOption>,
}

impl QuestionnaireQuestion {
    /// Formats one answer payload for dashboard display or CSV export.
    pub fn format_answer(&self, answers: Option<&QuestionnaireAnswers>) -> String {
        let Some(value) = answers.and_then(|answers| answers.get(self.id)) else {
            return String::new();
        };

        match (&self.kind, value) {
            (QuestionnaireQuestionKind::FreeText, QuestionnaireAnswerValue::One(value)) => {
                value.clone()
            }
            (QuestionnaireQuestionKind::SingleSelect, QuestionnaireAnswerValue::One(value)) => {
                Uuid::parse_str(value)
                    .ok()
                    .and_then(|option_id| self.option_label(option_id))
                    .map(str::to_string)
                    .unwrap_or_default()
            }
            (QuestionnaireQuestionKind::MultiSelect, QuestionnaireAnswerValue::Many(values)) => {
                values
                    .iter()
                    .filter_map(|option_id| self.option_label(*option_id))
                    .collect::<Vec<_>>()
                    .join(", ")
            }
            _ => String::new(),
        }
    }

    /// Returns a free-text answer for this question, if present.
    pub fn free_text_answer<'a>(
        &self,
        answers: Option<&'a QuestionnaireAnswers>,
    ) -> Option<&'a str> {
        match (self.kind, answers.and_then(|answers| answers.get(self.id))) {
            (QuestionnaireQuestionKind::FreeText, Some(QuestionnaireAnswerValue::One(value))) => {
                Some(value)
            }
            _ => None,
        }
    }

    /// Returns whether an option was selected for this question.
    pub fn is_option_selected(
        &self,
        answers: Option<&QuestionnaireAnswers>,
        option_id: &Uuid,
    ) -> bool {
        match answers.and_then(|answers| answers.get(self.id)) {
            Some(QuestionnaireAnswerValue::One(value)) => Uuid::parse_str(value)
                .is_ok_and(|selected_option_id| selected_option_id == *option_id),
            Some(QuestionnaireAnswerValue::Many(values)) => values.contains(option_id),
            None => false,
        }
    }

    /// Returns the display label for a selectable option.
    fn option_label(&self, option_id: Uuid) -> Option<&str> {
        self.options
            .iter()
            .find(|option| option.id == option_id)
            .map(|option| option.label.as_str())
    }

    /// Validates the submitted answer for this question.
    fn validate_answer(&self, answers: &QuestionnaireAnswers) -> Result<(), String> {
        let Some(value) = answers.get(self.id) else {
            if self.required {
                return Err("required questionnaire answer is missing".to_string());
            }

            return Ok(());
        };

        match (self.kind, value) {
            (QuestionnaireQuestionKind::FreeText, QuestionnaireAnswerValue::One(value)) => {
                if self.required && value.trim().is_empty() {
                    return Err("required questionnaire answer is empty".to_string());
                }
            }
            (QuestionnaireQuestionKind::SingleSelect, QuestionnaireAnswerValue::One(value)) => {
                let selected_option_id = Uuid::parse_str(value).map_err(|_| {
                    "single-select questionnaire answer must be an option id".to_string()
                })?;
                if !self.options.iter().any(|option| option.id == selected_option_id) {
                    return Err("questionnaire answer references an unknown option".to_string());
                }
            }
            (QuestionnaireQuestionKind::MultiSelect, QuestionnaireAnswerValue::Many(values)) => {
                if self.required && values.is_empty() {
                    return Err("required questionnaire answer is empty".to_string());
                }
                if values
                    .iter()
                    .any(|option_id| !self.options.iter().any(|option| option.id == *option_id))
                {
                    return Err("questionnaire answer references an unknown option".to_string());
                }
            }
            (QuestionnaireQuestionKind::FreeText, _) => {
                return Err("free-text questionnaire answer must be a string".to_string());
            }
            (QuestionnaireQuestionKind::SingleSelect, _) => {
                return Err("single-select questionnaire answer must be an option id".to_string());
            }
            (QuestionnaireQuestionKind::MultiSelect, _) => {
                return Err(
                    "multi-select questionnaire answer must be an option id array".to_string(),
                );
            }
        }

        Ok(())
    }
}

/// Answers to one questionnaire select question.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct QuestionnaireQuestionBreakdown {
    /// Question kind.
    pub kind: QuestionnaireQuestionKind,
    /// Selections per current option, in definition order.
    pub options: Vec<QuestionnaireOptionCount>,
    /// One-based position of the question among all questions.
    pub position: i64,
    /// Question prompt.
    pub prompt: String,
    /// Question identifier.
    pub question_id: Uuid,
    /// Respondents selecting at least one current option.
    pub respondents: i64,
    /// Selections of current options.
    pub selections: i64,
}

/// Supported questionnaire question types.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, strum::Display)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum QuestionnaireQuestionKind {
    /// Free-text input.
    FreeText,
    /// Multiple options can be selected.
    MultiSelect,
    /// One option can be selected.
    SingleSelect,
}

// Form types.

/// Form payload with optional encoded questionnaire answers.
#[derive(Debug, Clone, Default, Deserialize, Validate)]
pub(crate) struct OptionalQuestionnaireAnswersForm {
    /// Questionnaire answers decoded from the form field JSON.
    #[serde(
        default,
        deserialize_with = "deserialize_optional_questionnaire_answers"
    )]
    #[garde(custom(validate_optional_questionnaire_answers))]
    pub registration_answers: Option<QuestionnaireAnswers>,
}

/// Form-only answer payload that requires the top-level answers field.
#[derive(Deserialize)]
struct QuestionnaireAnswersFormPayload {
    /// Answers keyed by question identifier.
    answers: Vec<QuestionnaireAnswer>,
}

/// Form payload with required encoded questionnaire answers.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct RequiredQuestionnaireAnswersForm {
    /// Questionnaire answers decoded from the form field JSON.
    #[serde(deserialize_with = "deserialize_required_questionnaire_answers")]
    #[garde(custom(validate_questionnaire_answers))]
    pub registration_answers: QuestionnaireAnswers,
}

// Form helpers.

/// Deserializes an optional JSON-encoded questionnaire answers form field.
pub(crate) fn deserialize_optional_questionnaire_answers<'de, D>(
    deserializer: D,
) -> Result<Option<QuestionnaireAnswers>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<String>::deserialize(deserializer)?;
    value
        .as_deref()
        .filter(|value| !value.trim().is_empty())
        .map(parse_questionnaire_answers)
        .transpose()
        .map_err(D::Error::custom)
}

/// Deserializes a required JSON-encoded questionnaire answers form field.
pub(crate) fn deserialize_required_questionnaire_answers<'de, D>(
    deserializer: D,
) -> Result<QuestionnaireAnswers, D::Error>
where
    D: Deserializer<'de>,
{
    let value = String::deserialize(deserializer)?;
    if value.trim().is_empty() {
        return Err(D::Error::custom("questionnaire answers are required"));
    }

    parse_questionnaire_answers(&value).map_err(D::Error::custom)
}

/// Validates an optional decoded questionnaire answers payload.
pub(crate) fn validate_optional_questionnaire_answers(
    value: &Option<QuestionnaireAnswers>,
    _ctx: &(),
) -> garde::Result {
    if let Some(value) = value {
        value.validate_payload()?;
    }

    Ok(())
}

/// Validates a decoded questionnaire answers payload.
pub(crate) fn validate_questionnaire_answers(
    value: &QuestionnaireAnswers,
    _ctx: &(),
) -> garde::Result {
    value.validate_payload()
}

/// Parses questionnaire answers and requires the top-level answers array.
fn parse_questionnaire_answers(value: &str) -> Result<QuestionnaireAnswers, String> {
    let payload: QuestionnaireAnswersFormPayload =
        serde_json::from_str(value).map_err(|err| err.to_string())?;

    Ok(QuestionnaireAnswers {
        answers: payload.answers,
    })
}

#[cfg(test)]
mod tests {
    use garde::Validate;
    use serde_json::{Value, json};

    use super::*;

    #[test]
    fn test_optional_questionnaire_answers_form_deserializes_blank_as_none() {
        let form: OptionalQuestionnaireAnswersForm =
            serde_urlencoded::from_str("registration_answers=").unwrap();

        assert!(form.registration_answers.is_none());
    }

    #[test]
    fn test_required_questionnaire_answers_form_rejects_blank() {
        let result =
            serde_urlencoded::from_str::<RequiredQuestionnaireAnswersForm>("registration_answers=");

        assert!(result.is_err());
    }

    #[test]
    fn test_questionnaire_answers_form_requires_answers_array() {
        let result = serde_urlencoded::from_str::<OptionalQuestionnaireAnswersForm>(
            "registration_answers=%7B%7D",
        );

        assert!(result.is_err());
    }

    #[test]
    fn test_questionnaire_answers_payload_accepts_text_at_length_limit() {
        let answers = sample_text_answers("é".repeat(MAX_LEN_QUESTIONNAIRE_ANSWER));

        assert!(answers.validate_payload().is_ok());
    }

    #[test]
    fn test_questionnaire_answers_payload_rejects_duplicate_question_ids() {
        let question_id = Uuid::new_v4();
        let answers = QuestionnaireAnswers {
            answers: vec![
                QuestionnaireAnswer {
                    question_id,
                    value: QuestionnaireAnswerValue::One("First".to_string()),
                },
                QuestionnaireAnswer {
                    question_id,
                    value: QuestionnaireAnswerValue::One("Second".to_string()),
                },
            ],
        };
        let form = RequiredQuestionnaireAnswersForm {
            registration_answers: answers,
        };

        let report = form.validate().unwrap_err().to_string();
        assert!(
            report.contains("questionnaire answers must include each question at most once"),
            "{report}"
        );
    }

    #[test]
    fn test_questionnaire_answers_payload_rejects_text_above_length_limit() {
        let answers = sample_text_answers("a".repeat(MAX_LEN_QUESTIONNAIRE_ANSWER + 1));

        assert_eq!(
            answers.validate_payload().unwrap_err().to_string(),
            "free-text questionnaire answer is too long"
        );
    }

    #[test]
    fn test_questionnaire_answers_validate_against_questions_accepts_valid_answers() {
        let option_id = Uuid::new_v4();
        let question = sample_question(
            QuestionnaireQuestionKind::SingleSelect,
            true,
            vec![option_id],
        );
        let answers = QuestionnaireAnswers {
            answers: vec![QuestionnaireAnswer {
                question_id: question.id,
                value: QuestionnaireAnswerValue::One(option_id.to_string()),
            }],
        };

        assert!(answers.validate_against_questions(&[question]).is_ok());
    }

    #[test]
    fn test_questionnaire_answers_validate_against_questions_rejects_invalid_answers() {
        use QuestionnaireAnswerValue::{Many, One};
        use QuestionnaireQuestionKind::{FreeText, MultiSelect, SingleSelect};

        let option_id = Uuid::new_v4();
        let unknown_id = Uuid::new_v4();
        // (case, kind, required, answer value, expected error)
        let cases = [
            (
                "missing required answer",
                FreeText,
                true,
                None,
                "required questionnaire answer is missing",
            ),
            (
                "blank required free text",
                FreeText,
                true,
                Some(One("  ".to_string())),
                "required questionnaire answer is empty",
            ),
            (
                "free text given as options",
                FreeText,
                false,
                Some(Many(vec![option_id])),
                "free-text questionnaire answer must be a string",
            ),
            (
                "single select given as text",
                SingleSelect,
                false,
                Some(One("not-an-id".to_string())),
                "single-select questionnaire answer must be an option id",
            ),
            (
                "single select given as options",
                SingleSelect,
                false,
                Some(Many(vec![option_id])),
                "single-select questionnaire answer must be an option id",
            ),
            (
                "single select with unknown option",
                SingleSelect,
                false,
                Some(One(unknown_id.to_string())),
                "questionnaire answer references an unknown option",
            ),
            (
                "empty required multi select",
                MultiSelect,
                true,
                Some(Many(vec![])),
                "required questionnaire answer is empty",
            ),
            (
                "multi select given as text",
                MultiSelect,
                false,
                Some(One(option_id.to_string())),
                "multi-select questionnaire answer must be an option id array",
            ),
            (
                "multi select with unknown option",
                MultiSelect,
                false,
                Some(Many(vec![unknown_id])),
                "questionnaire answer references an unknown option",
            ),
            (
                "multi select repeating an option",
                MultiSelect,
                false,
                Some(Many(vec![option_id, option_id])),
                "multi-select questionnaire answers cannot repeat options",
            ),
        ];

        for (case, kind, required, value, expected) in cases {
            let question = sample_question(kind, required, vec![option_id]);
            let answers = QuestionnaireAnswers {
                answers: value
                    .into_iter()
                    .map(|value| QuestionnaireAnswer {
                        question_id: question.id,
                        value,
                    })
                    .collect(),
            };

            assert_eq!(
                answers.validate_against_questions(&[question]),
                Err(expected.to_string()),
                "{case}"
            );
        }
    }

    #[test]
    fn test_questionnaire_answers_validate_against_questions_rejects_unexpected_answers() {
        let answers = sample_text_answers("Answer".to_string());
        let question = sample_question(QuestionnaireQuestionKind::FreeText, false, vec![]);

        assert_eq!(
            answers.validate_against_questions(&[]),
            Err(
                "questionnaire answers cannot be submitted when questions are not configured"
                    .to_string()
            ),
            "questions not configured"
        );
        assert_eq!(
            answers.validate_against_questions(&[question]),
            Err("questionnaire answer references an unknown question".to_string()),
            "unknown question"
        );
        assert!(
            QuestionnaireAnswers::default()
                .validate_against_questions(&[])
                .is_ok(),
            "no answers without questions"
        );
    }

    #[test]
    fn test_questionnaire_question_format_answer_uses_option_labels() {
        use QuestionnaireAnswerValue::{Many, One};
        use QuestionnaireQuestionKind::{FreeText, MultiSelect, SingleSelect};

        let (blue, red) = (Uuid::new_v4(), Uuid::new_v4());
        // (case, kind, answer value, expected)
        let cases = [
            ("no answer", FreeText, None, ""),
            (
                "free text",
                FreeText,
                Some(One("Hello".to_string())),
                "Hello",
            ),
            (
                "single select",
                SingleSelect,
                Some(One(red.to_string())),
                "Red",
            ),
            (
                "single select with unknown option",
                SingleSelect,
                Some(One(Uuid::new_v4().to_string())),
                "",
            ),
            (
                "multi select",
                MultiSelect,
                Some(Many(vec![blue, Uuid::new_v4(), red])),
                "Blue, Red",
            ),
            (
                "mismatched value",
                MultiSelect,
                Some(One(red.to_string())),
                "",
            ),
        ];

        for (case, kind, value, expected) in cases {
            let question = QuestionnaireQuestion {
                options: vec![
                    QuestionnaireOption {
                        id: blue,
                        label: "Blue".to_string(),
                    },
                    QuestionnaireOption {
                        id: red,
                        label: "Red".to_string(),
                    },
                ],
                ..sample_question(kind, false, vec![])
            };
            let answers = QuestionnaireAnswers {
                answers: value
                    .into_iter()
                    .map(|value| QuestionnaireAnswer {
                        question_id: question.id,
                        value,
                    })
                    .collect(),
            };

            assert_eq!(question.format_answer(Some(&answers)), expected, "{case}");
        }
    }

    #[test]
    fn test_questionnaire_question_deserializes_valid_definition() {
        let question: QuestionnaireQuestion =
            serde_json::from_value(sample_question_json()).unwrap();

        assert_eq!(question.kind, QuestionnaireQuestionKind::SingleSelect);
        assert_eq!(question.options[0].label, "Option");
    }

    #[test]
    fn test_questionnaire_question_rejects_malformed_definitions() {
        // (case, field pointer, replacement; None removes the field)
        let cases = [
            ("missing kind", "/kind", None),
            ("non-string kind", "/kind", Some(json!(1))),
            ("null kind", "/kind", Some(Value::Null)),
            (
                "non-string option label",
                "/options/0/label",
                Some(json!(1)),
            ),
            ("non-string prompt", "/prompt", Some(json!(1))),
        ];

        for (case, pointer, replacement) in cases {
            let mut question = sample_question_json();
            match replacement {
                Some(value) => *question.pointer_mut(pointer).unwrap() = value,
                None => {
                    question.as_object_mut().unwrap().remove(&pointer[1..]);
                }
            }

            assert!(
                serde_json::from_value::<QuestionnaireQuestion>(question).is_err(),
                "{case}"
            );
        }
    }

    // Helpers.

    fn sample_question(
        kind: QuestionnaireQuestionKind,
        required: bool,
        option_ids: Vec<Uuid>,
    ) -> QuestionnaireQuestion {
        QuestionnaireQuestion {
            id: Uuid::new_v4(),
            kind,
            prompt: "Question?".to_string(),
            required,

            options: option_ids
                .into_iter()
                .map(|id| QuestionnaireOption {
                    id,
                    label: "Option".to_string(),
                })
                .collect(),
        }
    }

    /// Returns a valid single-select question definition as JSON.
    fn sample_question_json() -> Value {
        json!({
            "id": "00000000-0000-0000-0000-000000000001",
            "kind": "single-select",
            "options": [{"id": "00000000-0000-0000-0000-000000000002", "label": "Option"}],
            "prompt": "Question?",
            "required": true
        })
    }

    /// Returns an answers payload with one text value.
    fn sample_text_answers(value: String) -> QuestionnaireAnswers {
        QuestionnaireAnswers {
            answers: vec![QuestionnaireAnswer {
                question_id: Uuid::new_v4(),
                value: QuestionnaireAnswerValue::One(value),
            }],
        }
    }
}
