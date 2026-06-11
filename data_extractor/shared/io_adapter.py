# =============================================================================
# Google Drive Extractor IO Adapters
# =============================================================================

import pyparsing

if not hasattr(pyparsing, "DelimitedList"):
    pyparsing.DelimitedList = pyparsing.delimitedList

from googleapiclient.discovery import build
from google.cloud import storage
from datetime import datetime as dt
from zoneinfo import ZoneInfo
from typing import Any, TypeAlias

GoogleDriveService: TypeAlias = Any

# ------------------------------------------------------------
# INGESTION VALIDATION
# ------------------------------------------------------------


def extract_file(service: GoogleDriveService, file_id: str, mime_type: str) -> bytes:
    """
    Download or export file content from Google Drive into memory.

    Args:
        service: Authorized Google Drive API service instance.
        file_id: Unique Drive file identifier.
        mime_type: Determines the extraction method.

    Behavior:
    - Google Sheets: files().export_media -> server-side CSV conversion.
    - Binary/CSV files: files().get_media -> raw bytes.

    Returns:
        bytes: Raw file content.
    """

    if mime_type == "application/vnd.google-apps.spreadsheet":
        # for Google Sheets
        request = service.files().export_media(fileId=file_id, mimeType="text/csv")
    else:
        # for other file e.g. CSVs
        request = service.files().get_media(fileId=file_id)

    return request.execute()


def valid_handshake(service: GoogleDriveService, folder_id: str) -> bool:
    """
    Validate the instruction guard file marking uploader completion.

    Args:
        service: Authorized Google Drive API service instance.
        folder_id: ID of the date-suffixed directory to scan.

    Constraints:
        Text content decoded from bytes for string matching.

    Returns:
        bool: True if the instruction file exists and contains `file-upload=safe`. False otherwise.
    """

    query = f"'{folder_id}' in parents and name = 'instruction.txt'"
    results = service.files().list(q=query, fields="files(id, name)").execute()
    files = results.get("files", [])

    if not files:
        return False

    content = extract_file(service, files[0]["id"], "text/plain").decode("utf-8")

    return "file-upload=safe" in content


# ------------------------------------------------------------
# API UTILITIES
# ------------------------------------------------------------


def initialize_gdrive() -> GoogleDriveService:
    """
    Build a Google Drive API v3 service object.

    `cache_discovery=False` suppresses library warnings and improves container startup time.
    """

    return build("drive", "v3", cache_discovery=False)


def check_gcs_marking(bucket_name: str, blob_name: str) -> bool:
    """
    Check for a success marker in GCS.

    Args:
        bucket_name: Name of the archival bucket.
        blob_name: Path to the .success file (e.g., 'status/YYYY_MM_DD.success').

    Returns:
        bool: True if marker exists (folder already processed).
    """

    bucket_name = bucket_name.replace("gs://", "")
    client = storage.Client()
    bucket = client.bucket(bucket_name)

    return bucket.blob(blob_name).exists()


def upload_to_gcs(
    bucket_name: str,
    destination_name: str,
    data: str | bytes,
    content_type: str = "txt/csv",
) -> None:
    """
    Upload raw data CSVs or JSON files to a GCS bucket.

    Args:
        bucket_name: Target GCS bucket.
        destination_name: Full path/prefix for the new object.
        data: Content to upload.
        content_type: MIME type for GCS object metadata.
    """

    bucket_name = bucket_name.replace("gs://", "")

    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(destination_name)

    blob.upload_from_string(data, content_type=content_type)


def date_suffix(file_name: str) -> str:
    """
    Append today's Manila date (YYYY_MM_DD) to a file name.
    """

    pht_now = dt.now(ZoneInfo("Asia/Manila"))
    today = pht_now.strftime("%Y_%m_%d")
    return f"{file_name}_{today}"
