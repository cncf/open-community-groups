use axum::{
    body::to_bytes,
    http::{
        HeaderValue, StatusCode,
        header::{CONTENT_DISPOSITION, CONTENT_TYPE},
    },
};
use chrono::{TimeZone, Utc};

use super::{
    attachment_response, csv_optional_timestamp, csv_timestamp, csv_writer, finish_csv, safe_cell,
    write_safe_record,
};

#[tokio::test]
async fn test_attachment_response_sets_csv_download_headers() {
    // Build the attachment response
    let response = attachment_response("event-attendees.csv", b"Name\nJane\n".to_vec());
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the status, download headers and payload
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        &HeaderValue::from_static("text/csv; charset=utf-8"),
    );
    assert_eq!(
        parts.headers.get(CONTENT_DISPOSITION).unwrap(),
        &HeaderValue::from_static("attachment; filename=\"event-attendees.csv\""),
    );
    assert_eq!(bytes.as_ref(), b"Name\nJane\n");
}

#[test]
fn test_csv_optional_timestamp_formats_missing_value_as_empty_cell() {
    assert_eq!(csv_optional_timestamp(None), "");
}

#[test]
fn test_csv_optional_timestamp_formats_present_value() {
    let value = Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap();

    assert_eq!(csv_optional_timestamp(Some(value)), "2024-02-03 04:05 UTC");
}

#[test]
fn test_csv_timestamp_formats_utc_minutes() {
    let value = Utc.with_ymd_and_hms(2024, 12, 31, 23, 59, 59).unwrap();

    assert_eq!(csv_timestamp(value), "2024-12-31 23:59 UTC");
}

#[test]
fn test_csv_writer_terminates_records_with_lf() {
    // Write two records with the shared writer
    let mut writer = csv_writer();
    writer.write_record(["a", "b"]).unwrap();
    writer.write_record(["c", "d"]).unwrap();

    // Check records end with LF only
    assert_eq!(writer.into_inner().unwrap(), b"a,b\nc,d\n");
}

#[test]
fn test_safe_cell_keeps_safe_values_unchanged() {
    for value in [
        "",
        " =1+1",
        "1-2",
        "Jane Doe",
        "José 👋",
        "a=b",
        "user@example.com",
        "日本語",
    ] {
        assert_eq!(
            safe_cell(value),
            value,
            "value {value:?} should be unchanged"
        );
    }
}

#[test]
fn test_safe_cell_prefixes_every_dangerous_prefix() {
    for value in [
        "+1+1",
        "-1+1",
        "=SUM(A1:A2)",
        "@SUM(A1)",
        "\tTAB",
        "\nLF",
        "\rCR",
        "\u{0}NUL",
        "\u{1b}ESC",
        "\u{7f}DEL",
    ] {
        assert_eq!(
            safe_cell(value),
            format!("'{value}"),
            "value {value:?} should be prefixed",
        );
    }
}

#[test]
fn test_write_safe_record_neutralizes_headers_and_cells() {
    // Write a header and a row containing formula values
    let mut writer = csv_writer();
    write_safe_record(&mut writer, ["Name", "=Prompt"]).unwrap();
    write_safe_record(&mut writer, vec!["@Jane".to_string(), "-10".to_string()]).unwrap();

    // Check every dangerous cell is prefixed
    assert_eq!(
        String::from_utf8(finish_csv(writer).unwrap()).unwrap(),
        "Name,'=Prompt\n'@Jane,'-10\n",
    );
}

#[test]
fn test_write_safe_record_preserves_unicode() {
    // Write cells with non-ASCII characters
    let mut writer = csv_writer();
    write_safe_record(&mut writer, ["José", "日本語", "👋 Hello", "=Ünïcode"]).unwrap();

    // Check the UTF-8 values are written unchanged except for the formula guard
    assert_eq!(
        String::from_utf8(writer.into_inner().unwrap()).unwrap(),
        "José,日本語,👋 Hello,'=Ünïcode\n",
    );
}

#[test]
fn test_write_safe_record_quotes_delimiters_quotes_and_newlines() {
    // Write cells that need CSV quoting
    let mut writer = csv_writer();
    write_safe_record(
        &mut writer,
        [
            "Doe, Jane",
            "Example \"Cloud\"",
            "Principal\nEngineer",
            "\nLeading",
        ],
    )
    .unwrap();

    // Check quoting is preserved after neutralization
    assert_eq!(
        String::from_utf8(writer.into_inner().unwrap()).unwrap(),
        "\"Doe, Jane\",\"Example \"\"Cloud\"\"\",\"Principal\nEngineer\",\"'\nLeading\"\n",
    );
}
