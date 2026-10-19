//! Display helpers for questionnaire answer breakdowns, used by the
//! `breakdown` macro in `macros/question_answers.html`.

use std::cmp::Reverse;

use crate::{
    templates::helpers::{bar_width, percent_label},
    types::questionnaire::{QuestionnaireQuestionBreakdown, QuestionnaireQuestionKind},
};

/// Number of options shown for each question until expanded.
pub(crate) const QUESTION_VISIBLE_OPTIONS: usize = 10;

/// Selections of one question option, with its share of respondents.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct QuestionOptionShare {
    /// Selections of the option.
    pub count: i64,
    /// Whether the option is hidden until the question is expanded.
    pub hidden: bool,
    /// Option label.
    pub label: String,
    /// Share of respondents for display.
    pub share_label: String,
    /// Width percentage of the option bar.
    pub width: String,
}

/// Returns the number of question options hidden until expanded.
pub(crate) fn hidden_options_count(question: &QuestionnaireQuestionBreakdown) -> usize {
    question.options.len().saturating_sub(QUESTION_VISIBLE_OPTIONS)
}

/// Returns whether a question accepts several options per respondent.
///
/// Shares are computed over respondents, so the shares of a multi-select
/// question can add up to more than 100%.
pub(crate) fn is_multi_select(question: &QuestionnaireQuestionBreakdown) -> bool {
    question.kind == QuestionnaireQuestionKind::MultiSelect
}

/// Returns the options of a question by selections, most selected first, with
/// their share of respondents.
#[allow(clippy::cast_precision_loss)]
pub(crate) fn option_shares(question: &QuestionnaireQuestionBreakdown) -> Vec<QuestionOptionShare> {
    // Order options by selections, keeping the definition order on ties
    let mut options = question.options.iter().collect::<Vec<_>>();
    options.sort_by_key(|option| Reverse(option.count));

    // Describe each option with its share of respondents
    options
        .into_iter()
        .enumerate()
        .map(|(index, option)| {
            let share = if question.respondents > 0 {
                option.count as f64 / question.respondents as f64
            } else {
                0.0
            };
            QuestionOptionShare {
                count: option.count,
                hidden: index >= QUESTION_VISIBLE_OPTIONS,
                label: option.label.clone(),
                share_label: percent_label(Some(share)),
                width: bar_width(option.count, question.respondents),
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use uuid::Uuid;

    use crate::types::questionnaire::QuestionnaireOptionCount;

    use super::*;

    #[test]
    fn test_hidden_options_count_is_zero_within_the_visible_options() {
        let question = sample_question(QuestionnaireQuestionKind::SingleSelect, 1, &[1]);

        assert_eq!(hidden_options_count(&question), 0);
    }

    #[test]
    fn test_is_multi_select_matches_the_question_kind() {
        let multi_select = sample_question(QuestionnaireQuestionKind::MultiSelect, 1, &[1]);
        let single_select = sample_question(QuestionnaireQuestionKind::SingleSelect, 1, &[1]);

        assert!(is_multi_select(&multi_select));
        assert!(!is_multi_select(&single_select));
    }

    #[test]
    fn test_option_shares_hide_options_beyond_the_visible_ones() {
        // Setup a question with more options than the visible ones
        let question = sample_question(QuestionnaireQuestionKind::SingleSelect, 12, &[1; 12]);

        // Build the option shares
        let options = option_shares(&question);

        // Check the options past the visible ones start hidden
        assert_eq!(hidden_options_count(&question), 2);
        assert!(
            options[..QUESTION_VISIBLE_OPTIONS]
                .iter()
                .all(|option| !option.hidden)
        );
        assert!(options[QUESTION_VISIBLE_OPTIONS..].iter().all(|option| option.hidden));
        assert_eq!(options[11].label, "Option 11");
    }

    #[test]
    fn test_option_shares_sort_by_selections_with_shares_of_respondents() {
        // Setup a multi-select question whose shares add up to more than 100%
        let question = sample_question(QuestionnaireQuestionKind::MultiSelect, 4, &[1, 3, 1]);

        // Build the option shares
        let options = option_shares(&question);

        // Check the most selected option comes first, keeping ties in order
        assert_eq!(
            options,
            vec![
                QuestionOptionShare {
                    count: 3,
                    hidden: false,
                    label: "Option 1".to_string(),
                    share_label: "75%".to_string(),
                    width: "75.0".to_string(),
                },
                QuestionOptionShare {
                    count: 1,
                    hidden: false,
                    label: "Option 0".to_string(),
                    share_label: "25%".to_string(),
                    width: "25.0".to_string(),
                },
                QuestionOptionShare {
                    count: 1,
                    hidden: false,
                    label: "Option 2".to_string(),
                    share_label: "25%".to_string(),
                    width: "25.0".to_string(),
                },
            ]
        );
    }

    #[test]
    fn test_option_shares_use_zero_shares_without_respondents() {
        let question = sample_question(QuestionnaireQuestionKind::SingleSelect, 0, &[0]);

        let options = option_shares(&question);

        assert_eq!(options[0].share_label, "0%");
        assert_eq!(options[0].width, "0");
    }

    // Helpers.

    /// Returns a select question breakdown with one option per count.
    fn sample_question(
        kind: QuestionnaireQuestionKind,
        respondents: i64,
        counts: &[i64],
    ) -> QuestionnaireQuestionBreakdown {
        QuestionnaireQuestionBreakdown {
            kind,
            options: counts
                .iter()
                .enumerate()
                .map(|(index, count)| QuestionnaireOptionCount {
                    count: *count,
                    label: format!("Option {index}"),
                    option_id: Uuid::from_u128(100 + index as u128),
                })
                .collect(),
            position: 1,
            prompt: "Interests".to_string(),
            question_id: Uuid::from_u128(10),
            respondents,
            selections: counts.iter().sum(),
        }
    }
}
