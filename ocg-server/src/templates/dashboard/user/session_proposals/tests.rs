use askama::Template;
use uuid::Uuid;

use crate::{
    test_util::element_html_with,
    types::{
        dashboard::user::session_proposals::SessionProposal,
        pagination::NavigationLinks,
        tests::{sample_session_proposal, sample_session_proposal_levels},
    },
};

use super::ListPage;

#[test]
fn test_list_page_renders_compact_status_labels() {
    // Setup the cases: (case, status id, status name, compact label)
    let cases = [
        (
            "ready",
            "ready-for-submission",
            "Ready for submission",
            "Ready",
        ),
        (
            "declined",
            "declined-by-co-speaker",
            "Declined by co-speaker",
            "Declined",
        ),
        (
            "pending",
            "pending-co-speaker-response",
            "Pending co-speaker response",
            "Awaiting",
        ),
    ];

    for (case, status_id, status_name, compact) in cases {
        // Render an unlinked, unsubmitted proposal with the case status
        let session_proposal = SessionProposal {
            session_proposal_status_id: status_id.to_string(),
            status_name: status_name.to_string(),
            ..sample_session_proposal(Uuid::from_u128(1))
        };
        let html = ListPage {
            current_user_id: Uuid::from_u128(2),
            navigation_links: NavigationLinks::default(),
            pending_co_speaker_invitations: vec![],
            session_proposal_levels: sample_session_proposal_levels(),
            session_proposals: vec![session_proposal],
            total: 1,

            offset: None,
        }
        .render()
        .unwrap();

        // Check the badge pairs the hidden compact label with the full label
        let badge = element_html_with(&html, "custom-badge");
        assert!(
            badge.contains(r#"aria-hidden="true""#),
            "{case}: compact label is not hidden from assistive tech"
        );
        assert!(
            badge.contains(&format!(">{compact}</span>")),
            "{case}: compact label {compact:?} missing"
        );
        assert!(
            badge.contains(&format!(">{status_name}</span>")),
            "{case}: full label {status_name:?} missing"
        );
    }
}
