//! CSV helpers shared by dashboard download handlers.
//!
//! Spreadsheet applications evaluate a cell as a formula when its text starts
//! with `=`, `+`, `-` or `@`, and some also do so after a leading tab, carriage
//! return, line feed or another control character. Every cell written through
//! [`write_safe_record`], headers included, is protected by prefixing a single
//! quote to those values. Spreadsheets then display the cell as text: most hide
//! the leading quote, so `=1+1` reads `=1+1` instead of `2`, while plain-text
//! viewers show it. Negative numbers are therefore exported as text too
//! (`'-5`). Other values are written exactly as provided.

use std::borrow::Cow;

use axum::{
    http::header::{CONTENT_DISPOSITION, CONTENT_TYPE},
    response::{IntoResponse, Response},
};
use chrono::{DateTime, Utc};
use csv::{Terminator, Writer, WriterBuilder};

use crate::handlers::error::HandlerError;

#[cfg(test)]
mod tests;

/// Content type of CSV attachment responses.
const CSV_CONTENT_TYPE: &str = "text/csv; charset=utf-8";

/// Builds a CSV download response with the given file name and payload.
pub(crate) fn attachment_response(file_name: &str, body: Vec<u8>) -> Response {
    (
        [
            (CONTENT_TYPE, CSV_CONTENT_TYPE.to_string()),
            (
                CONTENT_DISPOSITION,
                format!("attachment; filename=\"{file_name}\""),
            ),
        ],
        body,
    )
        .into_response()
}

/// Formats an optional timestamp for CSV export, using an empty cell for none.
pub(crate) fn csv_optional_timestamp(value: Option<DateTime<Utc>>) -> String {
    value.map(csv_timestamp).unwrap_or_default()
}

/// Formats a timestamp for CSV export with minute precision in UTC.
pub(crate) fn csv_timestamp(value: DateTime<Utc>) -> String {
    value.format("%Y-%m-%d %H:%M UTC").to_string()
}

/// Returns an in-memory CSV writer that terminates records with LF.
pub(crate) fn csv_writer() -> Writer<Vec<u8>> {
    WriterBuilder::new()
        .terminator(Terminator::Any(b'\n'))
        .from_writer(vec![])
}

/// Flushes an in-memory CSV writer and returns the file contents.
pub(crate) fn finish_csv(writer: Writer<Vec<u8>>) -> Result<Vec<u8>, HandlerError> {
    writer.into_inner().map_err(|err| anyhow::Error::from(err).into())
}

/// Returns the cell value protected against spreadsheet formula evaluation.
///
/// Values starting with `=`, `+`, `-`, `@` or an ASCII control character
/// (including TAB, CR and LF) get a leading single quote; other values are
/// returned unchanged.
pub(crate) fn safe_cell(value: &str) -> Cow<'_, str> {
    match value.chars().next() {
        // Quote values that spreadsheets could evaluate as formulas
        Some('=' | '+' | '-' | '@') => Cow::Owned(format!("'{value}")),
        Some(first) if first.is_ascii_control() => Cow::Owned(format!("'{value}")),
        // Keep every other value as provided
        _ => Cow::Borrowed(value),
    }
}

/// Writes one CSV record, protecting every cell with [`safe_cell`].
pub(crate) fn write_safe_record<I, T>(
    writer: &mut Writer<Vec<u8>>,
    record: I,
) -> Result<(), HandlerError>
where
    I: IntoIterator<Item = T>,
    T: AsRef<str>,
{
    // Collect the cells so the protected values can borrow from them
    let cells: Vec<T> = record.into_iter().collect();

    // Write the protected cells as one record
    writer
        .write_record(cells.iter().map(|cell| match safe_cell(cell.as_ref()) {
            Cow::Borrowed(value) => Cow::Borrowed(value.as_bytes()),
            Cow::Owned(value) => Cow::Owned(value.into_bytes()),
        }))
        .map_err(anyhow::Error::from)?;

    Ok(())
}
