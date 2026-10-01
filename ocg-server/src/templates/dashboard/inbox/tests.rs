use askama::Template;
use uuid::Uuid;

use crate::types::{
    inbox::{InboxConversationStatus, InboxMessageKind},
    pagination::NavigationLinks,
    tests::{sample_inbox_conversation, sample_inbox_conversation_summary},
};

use super::*;

#[test]
fn test_action_done_notice_renders_reload_link() {
    let notice = ActionDoneNotice {
        message: "Message sent.".to_string(),
        reload_url: "/dashboard/group?tab=inbox&conversation_id=1".to_string(),
    };

    let body = notice.render().unwrap();

    assert!(body.contains("id=\"inbox-conversation\""));
    assert!(body.contains("Message sent."));
    assert!(body.contains("href=\"/dashboard/group?tab=inbox&#38;conversation_id=1\""));
}

#[test]
fn test_conversation_page_can_close_only_open_group_conversations() {
    let mut group_page = sample_conversation_page(InboxScope::Group);
    let user_page = sample_conversation_page(InboxScope::User);
    assert!(group_page.can_close());
    assert!(!user_page.can_close());

    group_page.conversation.status = InboxConversationStatus::Closed;
    assert!(!group_page.can_close());

    group_page.conversation.status = InboxConversationStatus::Spam;
    assert!(!group_page.can_close());
}

#[test]
fn test_conversation_page_can_mark_and_unmark_spam_only_in_group_scope() {
    let mut group_page = sample_conversation_page(InboxScope::Group);
    let mut user_page = sample_conversation_page(InboxScope::User);
    assert!(group_page.can_mark_spam());
    assert!(!group_page.can_unmark_spam());
    assert!(!user_page.can_mark_spam());

    group_page.conversation.status = InboxConversationStatus::Spam;
    user_page.conversation.status = InboxConversationStatus::Spam;

    assert!(!group_page.can_mark_spam());
    assert!(group_page.can_unmark_spam());
    assert!(!user_page.can_unmark_spam());
}

#[test]
fn test_conversation_page_can_reply_until_user_is_deleted() {
    let mut page = sample_conversation_page(InboxScope::Group);
    assert!(page.can_reply());

    page.conversation.user = None;

    assert!(!page.can_reply());
    assert_eq!(page.user_label(), "Deleted user");
}

#[test]
fn test_conversation_page_cannot_reply_to_spam() {
    let mut page = sample_conversation_page(InboxScope::User);

    page.conversation.status = InboxConversationStatus::Spam;

    assert!(!page.can_reply());
    assert!(page.is_spam());
}

#[test]
fn test_conversation_page_renders_action_notice_when_set() {
    let mut page = sample_conversation_page(InboxScope::Group);
    page.action_notice = Some("Conversation closed.".to_string());

    let body = page.render().unwrap();

    assert!(body.contains("data-inbox-action-notice>Conversation closed.</div>"));
    assert!(body.contains("role=\"status\""));
    assert!(body.contains("tabindex=\"-1\""));
    assert!(body.contains("autofocus"));
}

#[test]
fn test_conversation_page_renders_deleted_author_label() {
    let mut page = sample_conversation_page(InboxScope::Group);
    page.conversation.messages[0].author = None;

    let body = page.render().unwrap();

    assert!(body.contains("Deleted user"));
}

#[test]
fn test_conversation_page_renders_event_as_text_when_not_public() {
    let mut page = sample_conversation_page(InboxScope::User);
    page.conversation.event.as_mut().unwrap().is_public = false;

    let body = page.render().unwrap();

    assert!(body.contains("<span class=\"font-medium text-stone-700\">Test Event</span>"));
    assert!(!body.contains("/event/test-event"));
}

#[test]
fn test_conversation_page_renders_group_thread_with_reply_and_close() {
    let mut page = sample_conversation_page(InboxScope::Group);
    page.conversation.messages[0].body = "Line one\n<script>alert(1)</script>".to_string();
    let id = page.conversation.inbox_conversation_id;

    let body = page.render().unwrap();

    assert!(body.contains("id=\"inbox-conversation\""));
    assert!(body.contains("Inbox User"));
    assert!(body.contains("href=\"/test/group/test-group/event/test-event\""));
    assert!(body.contains("Line one\n&#60;script&#62;alert(1)&#60;/script&#62;"));
    assert!(body.contains(&format!("hx-post=\"/dashboard/group/inbox/{id}/replies\"")));
    assert!(body.contains(&format!("hx-put=\"/dashboard/group/inbox/{id}/close\"")));
    assert!(body.contains(&format!("hx-put=\"/dashboard/group/inbox/{id}/mark-spam\"")));
    assert!(!body.contains("/unmark-spam\""));
    assert!(body.contains("hx-target=\"#dashboard-layout\""));
    assert!(!body.contains("maxlength="));
    assert!(!body.contains("autofocus"));
    assert!(!body.contains("data-inbox-action-notice"));
    assert!(!body.contains("data-success-message=\"Conversation"));
}

#[test]
fn test_conversation_page_renders_organizer_tag_and_focus_after_message() {
    let mut page = sample_conversation_page(InboxScope::User);
    page.conversation.messages[0].kind = InboxMessageKind::GroupReply;
    page.focus_message = true;
    let id = page.conversation.inbox_conversation_id;

    let body = page.render().unwrap();

    assert!(body.contains(">Organizer</span>"));
    assert!(body.contains("autofocus"));
    assert!(body.contains(&format!("hx-post=\"/dashboard/user/inbox/{id}/messages\"")));
    assert!(!body.contains("/close\""));
    assert!(!body.contains("/mark-spam\""));
    assert!(body.contains("hx-target=\"body\""));
}

#[test]
fn test_conversation_page_renders_read_only_notice_for_deleted_users() {
    let mut page = sample_conversation_page(InboxScope::Group);
    page.conversation.user = None;

    let body = page.render().unwrap();

    assert!(body.contains("data-inbox-read-only-notice"));
    assert!(!body.contains("id=\"inbox-message-form\""));
    assert!(body.contains("id=\"inbox-close-button\""));
}

#[test]
fn test_conversation_page_renders_reopen_notice_for_closed_conversations() {
    let mut page = sample_conversation_page(InboxScope::User);
    page.conversation.status = InboxConversationStatus::Closed;

    let body = page.render().unwrap();

    assert!(body.contains("data-inbox-closed-notice"));
    assert!(body.contains("Sending a new message reopens it."));
    assert!(body.contains("id=\"inbox-message-form\""));
}

#[test]
fn test_conversation_page_renders_spam_notice_and_unmark_for_group() {
    let mut page = sample_conversation_page(InboxScope::Group);
    page.conversation.status = InboxConversationStatus::Spam;
    let id = page.conversation.inbox_conversation_id;

    let body = page.render().unwrap();

    assert!(body.contains("data-inbox-spam-notice"));
    assert!(body.contains("This conversation is marked as spam."));
    assert!(body.contains(">Spam</span>"));
    assert!(body.contains(&format!(
        "hx-put=\"/dashboard/group/inbox/{id}/unmark-spam\""
    )));
    assert!(!body.contains("/mark-spam\""));
    assert!(!body.contains("id=\"inbox-close-button\""));
    assert!(!body.contains("id=\"inbox-message-form\""));
}

#[test]
fn test_conversation_page_renders_spam_notice_without_form_for_user() {
    let mut page = sample_conversation_page(InboxScope::User);
    page.conversation.status = InboxConversationStatus::Spam;

    let body = page.render().unwrap();

    assert!(body.contains("data-inbox-spam-notice"));
    assert!(body.contains("The organizers marked this conversation as spam"));
    assert!(!body.contains("id=\"inbox-message-form\""));
    assert!(!body.contains("-spam\""));
}

#[test]
fn test_inbox_scope_urls() {
    let id = Uuid::nil();

    assert_eq!(
        InboxScope::Group.close_url(&id).as_deref(),
        Some("/dashboard/group/inbox/00000000-0000-0000-0000-000000000000/close")
    );
    assert_eq!(InboxScope::User.close_url(&id), None);
    assert_eq!(
        InboxScope::User.conversation_dashboard_url(&id),
        "/dashboard/user?tab=inbox&conversation_id=00000000-0000-0000-0000-000000000000"
    );
    assert_eq!(
        InboxScope::Group.conversation_url(&id),
        "/dashboard/group/inbox/00000000-0000-0000-0000-000000000000"
    );
    assert_eq!(
        InboxScope::Group.dashboard_url(),
        "/dashboard/group?tab=inbox"
    );
    assert_eq!(InboxScope::User.list_url(), "/dashboard/user/inbox");
    assert_eq!(
        InboxScope::Group.mark_spam_url(&id).as_deref(),
        Some("/dashboard/group/inbox/00000000-0000-0000-0000-000000000000/mark-spam")
    );
    assert_eq!(InboxScope::User.mark_spam_url(&id), None);
    assert_eq!(
        InboxScope::Group.message_url(&id),
        "/dashboard/group/inbox/00000000-0000-0000-0000-000000000000/replies"
    );
    assert_eq!(
        InboxScope::User.message_url(&id),
        "/dashboard/user/inbox/00000000-0000-0000-0000-000000000000/messages"
    );
    assert_eq!(
        InboxScope::Group.unmark_spam_url(&id).as_deref(),
        Some("/dashboard/group/inbox/00000000-0000-0000-0000-000000000000/unmark-spam")
    );
    assert_eq!(InboxScope::User.unmark_spam_url(&id), None);
}

#[test]
fn test_list_page_counterpart_label_per_scope() {
    let mut page = sample_list_page(InboxScope::Group);
    let mut conversation = page.conversations[0].clone();
    assert_eq!(page.counterpart_label(&conversation), "Inbox User");

    conversation.user = None;
    assert_eq!(page.counterpart_label(&conversation), "Deleted user");

    page.scope = InboxScope::User;
    assert_eq!(page.counterpart_label(&conversation), "Test Group");
}

#[test]
fn test_list_page_renders_empty_states() {
    let mut page = sample_list_page(InboxScope::Group);
    page.conversations = vec![];
    page.total = 0;
    assert!(page.render().unwrap().contains("No conversations yet"));

    page.status = Some(InboxConversationStatus::Answered);

    let body = page.render().unwrap();
    assert!(body.contains("No conversations with this status"));
    assert!(body.contains("Reset status filter"));
}

#[test]
fn test_list_page_renders_rows_linking_to_threads() {
    let page = sample_list_page(InboxScope::User);
    let id = page.conversations[0].inbox_conversation_id;

    let body = page.render().unwrap();

    assert!(body.contains(&format!("hx-get=\"/dashboard/user/inbox/{id}\"")));
    assert!(body.contains("Test Group"));
    assert!(body.contains("Test Event"));
    assert!(body.contains("When do doors open?"));
    assert!(body.contains(">Open</span>"));
}

#[test]
fn test_list_page_renders_spam_filter_only_for_group() {
    let group_page = sample_list_page(InboxScope::Group);
    let user_page = sample_list_page(InboxScope::User);

    assert!(group_page.render().unwrap().contains("value=\"spam\""));
    assert!(!user_page.render().unwrap().contains("value=\"spam\""));
}

#[test]
fn test_list_page_renders_warning_only_when_set() {
    let mut page = sample_list_page(InboxScope::User);
    assert!(
        !page
            .render()
            .unwrap()
            .contains("This conversation isn&#39;t in your Inbox.")
    );

    page.warning = Some("This conversation isn't in your Inbox.".to_string());

    assert!(
        page.render()
            .unwrap()
            .contains("This conversation isn&#39;t in your Inbox.")
    );
}

// Helpers.

/// Builds a conversation page for a public, open conversation.
fn sample_conversation_page(scope: InboxScope) -> ConversationPage {
    ConversationPage {
        conversation: sample_inbox_conversation(Uuid::new_v4()),
        focus_message: false,
        scope,

        action_notice: None,
    }
}

/// Builds a list page with one open conversation.
fn sample_list_page(scope: InboxScope) -> ListPage {
    ListPage {
        conversations: vec![sample_inbox_conversation_summary(Uuid::new_v4())],
        navigation_links: NavigationLinks::default(),
        scope,
        total: 1,

        offset: None,
        status: None,
        warning: None,
    }
}
