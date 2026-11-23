use std::{sync::Arc, time::Duration};

use anyhow::anyhow;
use tokio::sync::oneshot;
use uuid::Uuid;

use crate::{
    services::blocking::BlockingExecutor,
    test_util::sample_png,
    types::images::{Image, ImageTarget},
    util::compute_hash,
};

use super::{
    DefaultImagesManager, ImagesError, ImagesManager, MAX_IMAGE_SIZE_BYTES, MockImageStorage,
    UploadImageInput,
};

#[tokio::test]
async fn test_get_delegates_to_storage() {
    // Setup storage mock returning a stored image
    let expected = sample_image(sample_png(1, 1), "image/png");
    let mut storage = MockImageStorage::new();
    let stored = expected.clone();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "logo.png")
        .return_once(move |_| Box::pin(async move { Ok(Some(stored)) }));
    let manager = DefaultImagesManager::new(BlockingExecutor::new(1), Arc::new(storage));

    // Fetch the image through the manager
    let image = manager.get("logo.png").await.unwrap().unwrap();

    // Check the stored bytes and content type are returned unchanged
    assert_eq!(image.bytes, expected.bytes);
    assert_eq!(image.content_type, expected.content_type);
}

#[tokio::test]
async fn test_get_propagates_storage_error() {
    // Setup storage mock failing on lookup
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "logo.png")
        .returning(|_| Box::pin(async { Err(anyhow!("s3 unavailable")) }));
    let manager = DefaultImagesManager::new(BlockingExecutor::new(1), Arc::new(storage));

    // Fetch the image through the manager
    let err = manager.get("logo.png").await.unwrap_err();

    // Check unexpected storage failures stay wrapped in Other
    assert!(matches!(err, ImagesError::Other(_)), "got {err:?}");
}

#[tokio::test]
async fn test_upload_offloads_validation_and_hashing_to_blocking_executor() {
    // Setup a single-permit executor and occupy its only permit
    let executor = BlockingExecutor::new(1);
    let (entered_tx, entered_rx) = oneshot::channel();
    let (release_tx, release_rx) = std::sync::mpsc::channel();
    let blocker = {
        let executor = executor.clone();
        tokio::spawn(async move {
            executor
                .run(move || {
                    let _ = entered_tx.send(());
                    let _ = release_rx.recv();
                })
                .await
                .unwrap();
        })
    };
    entered_rx.await.unwrap();

    // Setup storage mock expecting the upload after the permit is released
    let bytes = sample_png(1, 1);
    let user_id = Uuid::new_v4();
    let expected_file_name = format!("{}.png", compute_hash(&bytes));
    let mut storage = MockImageStorage::new();
    let stored_name = expected_file_name.clone();
    storage
        .expect_save()
        .times(1)
        .withf(move |image| image.file_name == stored_name && image.user_id == user_id)
        .returning(|_| Box::pin(async { Ok(()) }));
    let manager = Arc::new(DefaultImagesManager::new(executor, Arc::new(storage)));

    // Start the upload while the blocking permit is busy
    let mut upload_task = {
        let manager = manager.clone();
        let bytes = bytes.clone();
        tokio::spawn(async move {
            manager
                .upload(UploadImageInput {
                    bytes,
                    file_name: "example.png".to_string(),
                    user_id,

                    target: None,
                })
                .await
        })
    };

    // Check upload waits on the blocking executor rather than running inline
    assert!(
        tokio::time::timeout(Duration::from_millis(25), &mut upload_task)
            .await
            .is_err(),
        "upload should wait while the blocking executor has no free permits"
    );

    // Release the permit and check the upload completes cleanly
    release_tx.send(()).unwrap();
    blocker.await.unwrap();
    let file_name = upload_task.await.unwrap().unwrap();
    assert_eq!(file_name, expected_file_name);
}

#[tokio::test]
async fn test_upload_propagates_storage_error() {
    // Setup storage mock failing on save
    let mut storage = MockImageStorage::new();
    storage
        .expect_save()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow!("s3 write failed")) }));
    let manager = DefaultImagesManager::new(BlockingExecutor::new(1), Arc::new(storage));

    // Attempt to upload a valid image when storage fails
    let err = manager
        .upload(UploadImageInput {
            bytes: sample_png(1, 1),
            file_name: "example.png".to_string(),
            user_id: Uuid::new_v4(),

            target: None,
        })
        .await
        .unwrap_err();

    // Check unexpected storage failures stay wrapped in Other
    assert!(matches!(err, ImagesError::Other(_)), "got {err:?}");
}

#[tokio::test]
async fn test_upload_rejects_invalid_image_without_saving() {
    // Setup storage mock that must not be written
    let mut storage = MockImageStorage::new();
    storage.expect_save().never();
    let manager = DefaultImagesManager::new(BlockingExecutor::new(1), Arc::new(storage));

    // Attempt to upload an image with wrong target dimensions
    let err = manager
        .upload(UploadImageInput {
            bytes: sample_png(1, 1),
            file_name: "example.png".to_string(),
            user_id: Uuid::new_v4(),

            target: Some(ImageTarget::OpenGraph),
        })
        .await
        .unwrap_err();

    // Check validation failure maps to a user-facing rejection
    assert!(
        matches!(
            &err,
            ImagesError::Rejected(msg) if msg == "image dimensions 1x1 do not match required 1200x630"
        ),
        "got {err:?}"
    );
}

#[tokio::test]
async fn test_upload_rejects_oversized_image_without_saving() {
    // Setup storage mock that must not be written
    let mut storage = MockImageStorage::new();
    storage.expect_save().never();
    let manager = DefaultImagesManager::new(BlockingExecutor::new(1), Arc::new(storage));

    // Attempt to upload a payload larger than the configured limit
    let err = manager
        .upload(UploadImageInput {
            bytes: vec![0; MAX_IMAGE_SIZE_BYTES + 1],
            file_name: "example.png".to_string(),
            user_id: Uuid::new_v4(),

            target: None,
        })
        .await
        .unwrap_err();

    // Check oversized payloads are rejected before storage
    assert!(
        matches!(&err, ImagesError::Rejected(msg) if msg == "image exceeds 1MB limit"),
        "got {err:?}"
    );
}

#[tokio::test]
async fn test_upload_validates_hashes_and_saves_image() {
    // Setup input and expected content-addressed file name
    let user_id = Uuid::new_v4();
    let bytes = sample_png(
        ImageTarget::OpenGraph.width(),
        ImageTarget::OpenGraph.height(),
    );
    let expected_file_name = format!("{}.png", compute_hash(&bytes));

    // Setup storage mock checking the saved payload
    let mut storage = MockImageStorage::new();
    let (expected_bytes, expected_name) = (bytes.clone(), expected_file_name.clone());
    storage
        .expect_save()
        .times(1)
        .withf(move |image| {
            image.bytes == expected_bytes
                && image.content_type == "image/png"
                && image.file_name == expected_name
                && image.user_id == user_id
        })
        .returning(|_| Box::pin(async { Ok(()) }));
    let manager = DefaultImagesManager::new(BlockingExecutor::new(1), Arc::new(storage));

    // Run the upload workflow
    let stored_file_name = manager
        .upload(UploadImageInput {
            bytes,
            file_name: "OPEN_GRAPH.PNG".to_string(),
            user_id,

            target: Some(ImageTarget::OpenGraph),
        })
        .await
        .unwrap();

    // Check the stored file name uses the content hash and lowercase extension
    assert_eq!(stored_file_name, expected_file_name);
}

#[tokio::test]
async fn test_validate_badge_artwork_accepts_valid_artwork() {
    // Setup storage mock with a valid 512x512 PNG
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .return_once(|_| {
            Box::pin(async { Ok(Some(sample_image(sample_png(512, 512), "image/png"))) })
        });
    let manager = DefaultImagesManager::new(BlockingExecutor::new(1), Arc::new(storage));

    // Validate the stored artwork
    let result = manager.validate_badge_artwork("badge.png").await;

    // Check valid artwork passes
    assert!(result.is_ok(), "got {result:?}");
}

#[tokio::test]
async fn test_validate_badge_artwork_offloads_decoding_to_blocking_executor() {
    // Setup a single-permit executor and occupy its only permit
    let executor = BlockingExecutor::new(1);
    let (entered_tx, entered_rx) = oneshot::channel();
    let (release_tx, release_rx) = std::sync::mpsc::channel();
    let blocker = {
        let executor = executor.clone();
        tokio::spawn(async move {
            executor
                .run(move || {
                    let _ = entered_tx.send(());
                    let _ = release_rx.recv();
                })
                .await
                .unwrap();
        })
    };
    entered_rx.await.unwrap();

    // Setup storage mock returning valid badge artwork
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .return_once(|_| {
            Box::pin(async { Ok(Some(sample_image(sample_png(512, 512), "image/png"))) })
        });
    let manager = Arc::new(DefaultImagesManager::new(executor, Arc::new(storage)));

    // Start artwork validation while the blocking permit is busy
    let mut validate_task = {
        let manager = manager.clone();
        tokio::spawn(async move { manager.validate_badge_artwork("badge.png").await })
    };

    // Check artwork decoding waits on the blocking executor
    assert!(
        tokio::time::timeout(Duration::from_millis(25), &mut validate_task)
            .await
            .is_err(),
        "artwork validation should wait while the blocking executor has no free permits"
    );

    // Release the permit and check validation succeeds
    release_tx.send(()).unwrap();
    blocker.await.unwrap();
    assert!(validate_task.await.unwrap().is_ok());
}

#[tokio::test]
async fn test_validate_badge_artwork_propagates_storage_error() {
    // Setup storage mock failing on lookup
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .returning(|_| Box::pin(async { Err(anyhow!("s3 read failed")) }));
    let manager = DefaultImagesManager::new(BlockingExecutor::new(1), Arc::new(storage));

    // Attempt to validate artwork when storage fails
    let err = manager.validate_badge_artwork("badge.png").await.unwrap_err();

    // Check unexpected storage failures stay wrapped in Other
    assert!(matches!(err, ImagesError::Other(_)), "got {err:?}");
}

#[tokio::test]
async fn test_validate_badge_artwork_rejects_invalid_artwork() {
    // Setup storage mock returning undersized artwork
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .return_once(|_| Box::pin(async { Ok(Some(sample_image(sample_png(1, 1), "image/png"))) }));
    let manager = DefaultImagesManager::new(BlockingExecutor::new(1), Arc::new(storage));

    // Validate the undersized artwork
    let err = manager.validate_badge_artwork("badge.png").await.unwrap_err();

    // Check invalid artwork maps to the user-facing message
    assert!(
        matches!(
            &err,
            ImagesError::Rejected(msg) if msg == "badge artwork must be a 512x512 PNG, JPEG, or WebP image"
        ),
        "got {err:?}"
    );
}

#[tokio::test]
async fn test_validate_badge_artwork_rejects_missing_artwork() {
    // Setup storage mock without the requested image
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "missing.png")
        .returning(|_| Box::pin(async { Ok(None) }));
    let manager = DefaultImagesManager::new(BlockingExecutor::new(1), Arc::new(storage));

    // Validate the missing artwork
    let err = manager.validate_badge_artwork("missing.png").await.unwrap_err();

    // Check missing artwork maps to a user-facing rejection
    assert!(
        matches!(&err, ImagesError::Rejected(msg) if msg == "badge artwork was not found"),
        "got {err:?}"
    );
}

// Helpers.

/// Builds a stored image fixture with the given bytes and content type.
fn sample_image(bytes: Vec<u8>, content_type: &str) -> Image {
    Image {
        bytes,
        content_type: content_type.to_string(),
    }
}
