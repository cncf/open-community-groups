//! Reusable questionnaire definitions and answer payloads.

#![allow(clippy::trivially_copy_pass_by_ref)]
#![allow(clippy::ref_option)]

use std::collections::HashSet;

use garde::Validate;
use serde::{Deserialize, Deserializer, Serialize, de::Error as DeError};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::validation::{MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_ENTITY_NAME, trimmed_non_empty};

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
    pub fn validate_against_questions(&self, questions: &[QuestionnaireQuestion]) -> Result<(), String> {
        self.validate_payload().map_err(|err| err.to_string())?;

        if questions.is_empty() {
            if self.answers.is_empty() {
                return Ok(());
            }

            return Err(
                "questionnaire answers cannot be submitted when questions are not configured".to_string(),
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
            if !question_ids.insert(answer.question_id) {
                return Err(garde::Error::new(
                    "questionnaire answers must include each question at most once",
                ));
            }

            if let QuestionnaireAnswerValue::Many(option_ids) = &answer.value {
                let mut selected_option_ids = HashSet::new();
                for option_id in option_ids {
                    if !selected_option_ids.insert(option_id) {
                        return Err(garde::Error::new(
                            "multi-select questionnaire answers cannot repeat options",
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
            (QuestionnaireQuestionKind::FreeText, QuestionnaireAnswerValue::One(value)) => value.clone(),
            (QuestionnaireQuestionKind::SingleSelect, QuestionnaireAnswerValue::One(value)) => {
                Uuid::parse_str(value)
                    .ok()
                    .and_then(|option_id| self.option_label(option_id))
                    .unwrap_or_default()
            }
            (QuestionnaireQuestionKind::MultiSelect, QuestionnaireAnswerValue::Many(values)) => values
                .iter()
                .filter_map(|option_id| self.option_label(*option_id))
                .collect::<Vec<_>>()
                .join(", "),
            _ => String::new(),
        }
    }

    /// Returns a free-text answer for this question, if present.
    pub fn free_text_answer<'a>(&self, answers: Option<&'a QuestionnaireAnswers>) -> Option<&'a str> {
        match (self.kind, answers.and_then(|answers| answers.get(self.id))) {
            (QuestionnaireQuestionKind::FreeText, Some(QuestionnaireAnswerValue::One(value))) => Some(value),
            _ => None,
        }
    }

    /// Returns whether an option was selected for this question.
    pub fn is_option_selected(&self, answers: Option<&QuestionnaireAnswers>, option_id: &Uuid) -> bool {
        match answers.and_then(|answers| answers.get(self.id)) {
            Some(QuestionnaireAnswerValue::One(value)) => {
                Uuid::parse_str(value).is_ok_and(|selected_option_id| selected_option_id == *option_id)
            }
            Some(QuestionnaireAnswerValue::Many(values)) => values.contains(option_id),
            None => false,
        }
    }

    /// Returns the display label for a selectable option.
    fn option_label(&self, option_id: Uuid) -> Option<String> {
        self.options
            .iter()
            .find(|option| option.id == option_id)
            .map(|option| option.label.clone())
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
                let selected_option_id = Uuid::parse_str(value)
                    .map_err(|_| "single-select questionnaire answer must be an option id".to_string())?;
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
                return Err("multi-select questionnaire answer must be an option id array".to_string());
            }
        }

        Ok(())
    }
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
#[derive(Debug, Default, Deserialize, Validate)]
pub(crate) struct OptionalQuestionnaireAnswersForm {
    /// Questionnaire answers decoded from the form field JSON.
    #[serde(default, deserialize_with = "deserialize_optional_questionnaire_answers")]
    #[garde(custom(validate_optional_questionnaire_answers))]
    pub registration_answers: Option<QuestionnaireAnswers>,
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
fn deserialize_optional_questionnaire_answers<'de, D>(
    deserializer: D,
) -> Result<Option<QuestionnaireAnswers>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<String>::deserialize(deserializer)?;
    parse_optional_questionnaire_answers(value.as_deref()).map_err(D::Error::custom)
}

/// Deserializes a required JSON-encoded questionnaire answers form field.
fn deserialize_required_questionnaire_answers<'de, D>(
    deserializer: D,
) -> Result<QuestionnaireAnswers, D::Error>
where
    D: Deserializer<'de>,
{
    let value = String::deserialize(deserializer)?;
    parse_required_questionnaire_answers(&value).map_err(D::Error::custom)
}

/// Parses optional questionnaire answers from a hidden form field value.
fn parse_optional_questionnaire_answers(value: Option<&str>) -> Result<Option<QuestionnaireAnswers>, String> {
    value
        .filter(|value| !value.trim().is_empty())
        .map(parse_questionnaire_answers)
        .transpose()
}

/// Parses required questionnaire answers from a hidden form field value.
fn parse_required_questionnaire_answers(value: &str) -> Result<QuestionnaireAnswers, String> {
    if value.trim().is_empty() {
        return Err("questionnaire answers are required".to_string());
    }

    parse_questionnaire_answers(value)
}

/// Parses questionnaire answers and requires the top-level answers array.
fn parse_questionnaire_answers(value: &str) -> Result<QuestionnaireAnswers, String> {
    let json: serde_json::Value = serde_json::from_str(value).map_err(|err| err.to_string())?;
    if !json
        .get("answers")
        .is_some_and(|answers| matches!(answers, serde_json::Value::Array(_)))
    {
        return Err("questionnaire answers must contain an answers array".to_string());
    }

    serde_json::from_value(json).map_err(|err| err.to_string())
}

/// Validates a decoded questionnaire answers payload.
fn validate_questionnaire_answers(value: &QuestionnaireAnswers, _ctx: &()) -> garde::Result {
    value.validate_payload()
}

/// Validates an optional decoded questionnaire answers payload.
fn validate_optional_questionnaire_answers(value: &Option<QuestionnaireAnswers>, _ctx: &()) -> garde::Result {
    if let Some(value) = value {
        value.validate_payload()?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use garde::Validate;

    use super::*;

    #[test]
    fn test_optional_questionnaire_answers_form_deserializes_blank_as_none() {
        let form: OptionalQuestionnaireAnswersForm =
            serde_urlencoded::from_str("registration_answers=").unwrap();

        assert!(form.registration_answers.is_none());
    }

    #[test]
    fn test_required_questionnaire_answers_form_rejects_blank() {
        let result = serde_urlencoded::from_str::<RequiredQuestionnaireAnswersForm>("registration_answers=");

        assert!(result.is_err());
    }

    #[test]
    fn test_questionnaire_answers_form_requires_answers_array() {
        let result =
            serde_urlencoded::from_str::<OptionalQuestionnaireAnswersForm>("registration_answers=%7B%7D");

        assert!(result.is_err());
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

        assert!(form.validate().is_err());
    }

    #[test]
    fn test_questionnaire_answers_validate_against_questions_accepts_valid_answers() {
        let option_id = Uuid::new_v4();
        let question = sample_question(QuestionnaireQuestionKind::SingleSelect, true, vec![option_id]);
        let answers = QuestionnaireAnswers {
            answers: vec![QuestionnaireAnswer {
                question_id: question.id,
                value: QuestionnaireAnswerValue::One(option_id.to_string()),
            }],
        };

        assert!(answers.validate_against_questions(&[question]).is_ok());
    }

    #[test]
    fn test_questionnaire_answers_validate_against_questions_rejects_missing_required_answer() {
        let question = sample_question(QuestionnaireQuestionKind::FreeText, true, vec![]);
        let answers = QuestionnaireAnswers::default();

        assert_eq!(
            answers.validate_against_questions(&[question]),
            Err("required questionnaire answer is missing".to_string())
        );
    }

    #[test]
    fn test_questionnaire_answers_validate_against_questions_rejects_unknown_option() {
        let question = sample_question(
            QuestionnaireQuestionKind::MultiSelect,
            false,
            vec![Uuid::new_v4()],
        );
        let answers = QuestionnaireAnswers {
            answers: vec![QuestionnaireAnswer {
                question_id: question.id,
                value: QuestionnaireAnswerValue::Many(vec![Uuid::new_v4()]),
            }],
        };

        assert_eq!(
            answers.validate_against_questions(&[question]),
            Err("questionnaire answer references an unknown option".to_string())
        );
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
}
