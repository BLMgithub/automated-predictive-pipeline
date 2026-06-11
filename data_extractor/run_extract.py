# =============================================================================
# Google Drive Extractor Orchestrator
# =============================================================================

import sys
import json
import uuid
from data_extractor.shared.io_adapter import (
    initialize_gdrive,
    check_gcs_marking,
    upload_to_gcs,
    date_suffix,
)

from data_extractor.shared.extract_logic import (
    MARKET_BUCKET,
    get_target_folder_id,
    get_valid_files,
    process_extraction,
)


def orchestrate_extract(target_folder: str) -> int:
    """
    docstring...
    """

    service = initialize_gdrive()
    metadata_path = f"logs/{target_folder}_metatdata.json"
    marketing_flag_path = f"status/{target_folder}.success"

    metadata = {
        "execution_id": str(uuid.uuid4()),
        "files_processed": [],
        "errors": [],
        "status": "",
    }

    # Deduplication check
    if check_gcs_marking(MARKET_BUCKET, marketing_flag_path):
        print(f"[INFO]: {target_folder} already processed.")
        return 0

    # Extract and validate target folder id
    folder_id = get_target_folder_id(target_folder, service)
    if not folder_id:
        return 1

    # Extract and validate handshake and files
    files_in_drive = get_valid_files(folder_id, target_folder, service)
    if files_in_drive is None or len(files_in_drive) == 0:
        return 1

    for file in files_in_drive:

        market_bucket_path = f"data/{file['name']}"

        ok, details = process_extraction(
            file=file,
            drive_api=service,
            marketing_bucket_path=market_bucket_path,
        )

        if ok:
            metadata["files_processed"].append(details)
        else:
            metadata["errors"].append(details)
            metadata["status"] = "failed"

            # Upload run metadata on Failure
            upload_to_gcs(MARKET_BUCKET, metadata_path, json.dumps(metadata))
            return 1

    # Upload run metadata on Success
    upload_to_gcs(MARKET_BUCKET, metadata_path, json.dumps(metadata))
    print(f"[SUCCESS]: files from '{target_folder}' completely processed.")
    return 0


def main():

    target_folder = date_suffix(file_name="marketing_campaigns")
    print(f"[INFO]: Starting extraction for folder: {target_folder}")

    exit_code = orchestrate_extract(target_folder)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
