# =============================================================================
# Google Drive Extractor Logic
# =============================================================================

from typing import List, Dict
from data_extractor.shared.io_adapter import (
    extract_file,
    valid_handshake,
    upload_to_gcs,
    GoogleDriveService,
)

MARKET_BUCKET = "gs://marketing-archival-dev"
ROOT_FOLDER = "marketing_upload-folder"
MIME_TYPE = "application/vnd.google-apps.folder"


def get_target_folder_id(folder_name: str, drive_api: GoogleDriveService) -> str | None:
    """
    Resolve a Drive folder ID by name inside ROOT_FOLDER.

    Only searches children of ROOT_FOLDER so folders with the same name elsewhere in Drive don't collide.

    Returns None when the root or target folder is missing.
    """

    # Find Root folder
    root_query = f"name = '{ROOT_FOLDER}' and mimeType= '{MIME_TYPE}'"
    root_query_result = (
        drive_api.files().list(q=root_query, fields="files(id)").execute()
    )
    root_files = root_query_result.get("files", [])

    if not root_files:
        print(f"[ERROR]: Root folder '{ROOT_FOLDER}' not found or not shared.")
        return None

    root_id = root_files[0]["id"]

    # Find target folder inside root folder
    target_query = f"name = '{folder_name}' and '{root_id}' in parents and mimeType = '{MIME_TYPE}'"
    target_query_result = (
        drive_api.files().list(q=target_query, fields="files(id)").execute()
    )
    target_files = target_query_result.get("files", [])

    if not target_files:
        print(f"[ERROR]: folder '{folder_name}' not found inside '{ROOT_FOLDER}'.")
        return None

    return target_files[0]["id"]


def get_valid_files(
    folder_id: str,
    folder_name: str,
    drive_api: GoogleDriveService,
) -> List[Dict] | None:
    """
    Return non-instruction files from a Drive folder.

    Contract:
    - valid_handshake must pass before listing begins.
    - instruction.txt is excluded from results.
    - Only direct children are listed; subfolders are not traversed.

    Invariants:
    - Return is None (handshake failed) or List[Dict] (may be empty).
    - An empty list means instruction.txt was the only file present.

    Failures:
    - Handshake failure returns None with an [ERROR] log.
    - Empty folder returns [] with a [WARNING] log.
    - API errors propagate as unhandled exceptions.
    """

    # Check instruction.txt inside
    if not valid_handshake(drive_api, folder_id):
        print(f"[ERROR] '{folder_name}' missing instruction.txt or upload not safe")
        return None

    # List all files within folder
    folder_files = (
        drive_api.files()
        .list(
            q=f"'{folder_id}' in parents and name != 'instruction.txt'",
            fields="files(id, name, mimeType)",
        )
        .execute()
    )

    files_in_drive = folder_files.get("files", [])

    # Warn if folder but emplty
    if not files_in_drive:
        print(f"[WARNING]: '{folder_name}' is empty. Nothing to process. Exiting")

    return files_in_drive


def process_extraction(
    file: dict, drive_api: GoogleDriveService, marketing_bucket_path: str
) -> tuple[bool, dict]:
    """
    Download a Drive file and upload it to GCS.

    extract_file runs first, then upload_to_gcs. Both must succeed for a True result.
    Exceptions in either step are caught and returned as error_details;
    no exception propagates to the caller.

    Invariants:
    - Return is always tuple[bool, dict].
    - True result: {"name": str, "status": "success"}.
    - False result: includes file_name, drive_id, error_type, error_message.

    Failures:
    - Any exception in extract_file or upload_to_gcs: caught, logged,
      returned as (False, error_details). Never propagates.
    """

    try:
        data = extract_file(drive_api, file["id"], file["mimeType"])

        upload_to_gcs(MARKET_BUCKET, marketing_bucket_path, data)
        print(f"[INFO]: file '{file['name']}' extracted successfully.")
        success_details = {"name": file["name"], "status": "success"}

        return True, success_details

    except Exception as e:
        print(f"[ERROR]: Execution halted on file '{file['name']}': {str(e)}")

        error_details = {
            "file_name": file["name"],
            "drive_id": file["id"],
            "error_type": type(e).__name__,
            "error_message": str(e),
        }

    return False, error_details
