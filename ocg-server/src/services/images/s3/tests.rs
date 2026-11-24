use std::{future::Future, time::Duration};

use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    sync::oneshot,
    task::JoinHandle,
    time::{Instant, sleep, timeout},
};
use uuid::Uuid;

use super::*;

#[test]
fn test_s3_image_storage_configures_client_timeouts() {
    // Setup S3 configuration with custom connect and request deadlines
    let cfg = sample_s3_cfg("http://127.0.0.1:9000", 7, 19);

    // Build the storage client
    let storage = S3ImageStorage::new(&cfg);

    // Check every outbound SDK deadline and the body-read deadline match config
    let timeout_config = storage
        .client
        .config()
        .timeout_config()
        .expect("timeout config to be configured");
    assert_eq!(
        timeout_config.connect_timeout(),
        Some(Duration::from_secs(7))
    );
    assert_eq!(timeout_config.read_timeout(), Some(Duration::from_secs(19)));
    assert_eq!(
        timeout_config.operation_attempt_timeout(),
        Some(Duration::from_secs(19))
    );
    assert_eq!(
        timeout_config.operation_timeout(),
        Some(Duration::from_secs(19))
    );
    assert_eq!(storage.request_timeout, Duration::from_secs(19));
}

#[tokio::test]
async fn test_s3_image_storage_get_returns_image_within_deadline() {
    // Setup a local S3 server returning a complete object response
    let body = b"png-image-bytes".to_vec();
    let expected_body = body.clone();
    let (endpoint, shutdown_tx, server_handle) =
        spawn_test_s3_server(move |mut stream, _shutdown| async move {
            read_http_request_headers(&mut stream).await;
            let response = format!(
                concat!(
                    "HTTP/1.1 200 OK\r\n",
                    "Content-Type: image/png\r\n",
                    "Content-Length: {}\r\n",
                    "Connection: close\r\n\r\n",
                ),
                body.len()
            );
            stream.write_all(response.as_bytes()).await.unwrap();
            stream.write_all(&body).await.unwrap();
            stream.flush().await.unwrap();
        })
        .await;
    let storage = S3ImageStorage::new(&sample_s3_cfg(&endpoint, 2, 2));

    // Fetch the image from the mock S3 server
    let image = storage.get("logo.png").await.unwrap().expect("image to be returned");

    // Check the image content and clean up the server task
    assert_eq!(image.bytes, expected_body);
    assert_eq!(image.content_type, "image/png");
    let _ = shutdown_tx.send(());
    server_handle.await.unwrap();
}

#[tokio::test]
async fn test_s3_image_storage_get_returns_none_on_no_such_key() {
    // Setup a local S3 server returning a NoSuchKey 404 XML response
    let (endpoint, shutdown_tx, server_handle) =
        spawn_test_s3_server(|mut stream, _shutdown| async move {
            read_http_request_headers(&mut stream).await;
            let xml = concat!(
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                "<Error><Code>NoSuchKey</Code><Message>Not found</Message></Error>",
            );
            let response = format!(
                concat!(
                    "HTTP/1.1 404 Not Found\r\n",
                    "Content-Type: application/xml\r\n",
                    "Content-Length: {}\r\n",
                    "Connection: close\r\n\r\n{}",
                ),
                xml.len(),
                xml
            );
            stream.write_all(response.as_bytes()).await.unwrap();
            stream.flush().await.unwrap();
        })
        .await;
    let storage = S3ImageStorage::new(&sample_s3_cfg(&endpoint, 2, 2));

    // Fetch a missing image key
    let result = storage.get("missing.png").await.unwrap();

    // Check NoSuchKey maps to None and clean up the server task
    assert!(result.is_none());
    let _ = shutdown_tx.send(());
    server_handle.await.unwrap();
}

#[tokio::test]
async fn test_s3_image_storage_get_shares_request_deadline_between_headers_and_body() {
    // Setup a local S3 server that delays headers before stalling the body stream
    let (endpoint, shutdown_tx, server_handle) =
        spawn_test_s3_server(|mut stream, mut shutdown| async move {
            tokio::select! {
                () = read_http_request_headers(&mut stream) => {}
                _ = &mut shutdown => return,
            }
            tokio::select! {
                () = sleep(Duration::from_millis(600)) => {}
                _ = &mut shutdown => return,
            }
            let response = concat!(
                "HTTP/1.1 200 OK\r\n",
                "Content-Type: image/png\r\n",
                "Content-Length: 1024\r\n\r\n",
                "partial",
            );
            if stream.write_all(response.as_bytes()).await.is_ok() {
                let _ = stream.flush().await;
                let _ = shutdown.await;
            }
        })
        .await;
    let storage = S3ImageStorage::new(&sample_s3_cfg(&endpoint, 2, 1));

    // Fetch the image and measure total elapsed time across headers and body read
    let started_at = Instant::now();
    let err = timeout(Duration::from_secs(5), storage.get("slow-then-stalled.png"))
        .await
        .expect("stalled body read to time out before test guard")
        .unwrap_err();
    let elapsed = started_at.elapsed();

    // Check the body read used only the remaining request budget instead of a second full timeout
    assert_eq!(err.to_string(), "timed out reading s3 object body");
    assert!(
        elapsed < Duration::from_millis(1400),
        "expected shared 1s request deadline, elapsed: {elapsed:?}"
    );
    let _ = shutdown_tx.send(());
    server_handle.await.unwrap();
}

#[tokio::test]
async fn test_s3_image_storage_get_times_out_when_body_read_stalls() {
    // Setup a local S3 server that sends 200 OK headers and stalls mid-body
    let (endpoint, shutdown_tx, server_handle) =
        spawn_test_s3_server(|mut stream, mut shutdown| async move {
            tokio::select! {
                () = read_http_request_headers(&mut stream) => {}
                _ = &mut shutdown => return,
            }
            let response = concat!(
                "HTTP/1.1 200 OK\r\n",
                "Content-Type: image/png\r\n",
                "Content-Length: 1024\r\n\r\n",
                "partial",
            );
            if stream.write_all(response.as_bytes()).await.is_ok() {
                let _ = stream.flush().await;
                let _ = shutdown.await;
            }
        })
        .await;
    let storage = S3ImageStorage::new(&sample_s3_cfg(&endpoint, 2, 1));

    // Fetch the image and guard the test against an unbounded hang
    let err = timeout(Duration::from_secs(5), storage.get("stalled.png"))
        .await
        .expect("stalled body read to time out before test guard")
        .unwrap_err();

    // Check the body-read timeout error context and clean up the server task
    assert_eq!(err.to_string(), "timed out reading s3 object body");
    let _ = shutdown_tx.send(());
    server_handle.await.unwrap();
}

#[tokio::test]
async fn test_s3_image_storage_get_times_out_when_headers_stall() {
    // Setup a local S3 server that accepts the connection and never responds
    let (endpoint, shutdown_tx, server_handle) =
        spawn_test_s3_server(|mut stream, mut shutdown| async move {
            tokio::select! {
                () = read_http_request_headers(&mut stream) => {}
                _ = &mut shutdown => return,
            }
            let _ = shutdown.await;
        })
        .await;
    let storage = S3ImageStorage::new(&sample_s3_cfg(&endpoint, 2, 1));

    // Fetch the image and guard the test against an unbounded hang
    let err = timeout(Duration::from_secs(5), storage.get("slow.png"))
        .await
        .expect("stalled headers read to time out before test guard")
        .unwrap_err();

    // Check the SDK timed out the request and clean up the server task
    let err_chain = format!("{err:#}");
    assert!(
        err_chain.contains("timeout") || err_chain.contains("timed out"),
        "expected timeout error, got: {err_chain}"
    );
    let _ = shutdown_tx.send(());
    server_handle.await.unwrap();
}

#[tokio::test]
async fn test_s3_image_storage_save_times_out_when_response_stalls() {
    // Setup a local S3 server that reads headers and never responds to PUT
    let (endpoint, shutdown_tx, server_handle) =
        spawn_test_s3_server(|mut stream, mut shutdown| async move {
            tokio::select! {
                () = read_http_request_headers(&mut stream) => {}
                _ = &mut shutdown => return,
            }
            let _ = shutdown.await;
        })
        .await;
    let storage = S3ImageStorage::new(&sample_s3_cfg(&endpoint, 2, 1));
    let image = NewImage {
        bytes: b"png-image-bytes",
        content_type: "image/png",
        file_name: "upload.png",
        user_id: Uuid::nil(),
    };

    // Upload the image and guard the test against an unbounded hang
    let err = timeout(Duration::from_secs(5), storage.save(&image))
        .await
        .expect("stalled upload to time out before test guard")
        .unwrap_err();

    // Check the SDK timed out the upload and clean up the server task
    let err_chain = format!("{err:#}");
    assert!(
        err_chain.contains("timeout") || err_chain.contains("timed out"),
        "expected timeout error, got: {err_chain}"
    );
    let _ = shutdown_tx.send(());
    server_handle.await.unwrap();
}

// Helpers.

/// Read from a test socket until the HTTP request header terminator arrives.
async fn read_http_request_headers(stream: &mut TcpStream) {
    let mut buf = Vec::new();
    let mut chunk = [0_u8; 1024];
    while !buf.windows(4).any(|window| window == b"\r\n\r\n") {
        let Ok(read) = stream.read(&mut chunk).await else {
            break;
        };
        if read == 0 {
            break;
        }
        buf.extend_from_slice(&chunk[..read]);
    }
}

/// Build a sample S3 image storage configuration pointing at the given endpoint.
fn sample_s3_cfg(
    endpoint: &str,
    connect_timeout_secs: u64,
    request_timeout_secs: u64,
) -> ImageStorageConfigS3 {
    ImageStorageConfigS3 {
        access_key_id: "test-access-key".to_string(),
        bucket: "images".to_string(),
        region: "us-east-1".to_string(),
        secret_access_key: "test-secret-key".to_string(),

        connect_timeout_secs,
        endpoint: Some(endpoint.to_string()),
        force_path_style: Some(true),
        request_timeout_secs,
    }
}

/// Spawn a single-connection local TCP server mimicking an S3 endpoint.
async fn spawn_test_s3_server<F, Fut>(handler: F) -> (String, oneshot::Sender<()>, JoinHandle<()>)
where
    F: FnOnce(TcpStream, oneshot::Receiver<()>) -> Fut + Send + 'static,
    Fut: Future<Output = ()> + Send + 'static,
{
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let (shutdown_tx, mut shutdown_rx) = oneshot::channel();
    let handle = tokio::spawn(async move {
        let accepted = tokio::select! {
            result = listener.accept() => result.ok(),
            _ = &mut shutdown_rx => None,
        };
        if let Some((stream, _)) = accepted {
            handler(stream, shutdown_rx).await;
        }
    });

    (format!("http://{addr}"), shutdown_tx, handle)
}
