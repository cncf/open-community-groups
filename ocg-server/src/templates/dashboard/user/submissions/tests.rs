use askama::Template;
use uuid::Uuid;

use crate::{
    test_util::element_text_with,
    types::{
        dashboard::user::submissions::CfsSubmission, event::EventLabel,
        pagination::NavigationLinks, tests::sample_user_cfs_submission,
    },
};

use super::ListPage;

#[test]
fn test_list_page_renders_compact_status_and_labels_summary() {
    // Setup an information request with two labels
    let cfs_submission_id = Uuid::from_u128(1);
    let submission = CfsSubmission {
        labels: vec![
            EventLabel {
                color: "#DBEAFE".to_string(),
                event_label_id: Uuid::from_u128(4),
                name: "Security".to_string(),
            },
            EventLabel {
                color: "#FEE2E2".to_string(),
                event_label_id: Uuid::from_u128(5),
                name: "Cloud native".to_string(),
            },
        ],
        status_id: "information-requested".to_string(),
        status_name: "Information requested".to_string(),
        ..sample_user_cfs_submission(cfs_submission_id, Uuid::from_u128(2), Uuid::from_u128(3))
    };

    // Render the list page
    let html = ListPage {
        navigation_links: NavigationLinks::default(),
        submissions: vec![submission],
        total: 1,

        offset: None,
    }
    .render()
    .unwrap();

    // Check the status renders both the compact and the full label
    assert!(html.contains(">Info requested</span>"));
    assert!(html.contains("Information requested"));

    // Check the labels summary trigger counts the labels and names its tooltip
    let tooltip_id = format!("user-submission-labels-{cfs_submission_id}");
    let trigger_needle = format!(r#"aria-describedby="{tooltip_id}""#);
    assert_eq!(element_text_with(&html, &trigger_needle), "2 labels");

    // Check the tooltip lists every label
    let tooltip_text = element_text_with(&html, &format!(r#"id="{tooltip_id}""#));
    assert!(tooltip_text.contains("Security"));
    assert!(tooltip_text.contains("Cloud native"));
}
