# Data Extractor Stage

**Files:**
- **Executor:** [`run_extract.py`](../../data_extractor/run_extract.py)
- **Logic:** [`shared/extract_logic.py`](../../data_extractor/shared/extract_logic.py)
- **I/O Adapter:** [`shared/io_adapter.py`](../../data_extractor/shared/io_adapter.py)

**Role:** Extracts marketing CSV files from a date-suffixed Google Drive folder and uploads them to a GCS archival bucket, with a deduplication gate and fail-fast error propagation.

## 1. System Contract

**Purpose**
Daily ingestion of marketing campaign spreadsheets from Google Drive into GCS. The stage enforces an upload-safety handshake (`instruction.txt` must contain `file-upload=safe`), resists duplicate execution via a GCS success marker, and generates per-run lineage metadata.

**Invariants**
- Each invocation produces a UUID4 `execution_id` recorded in run metadata.
- `instruction.txt` is never included in the extracted file list.
- Only direct children of the target Drive folder are listed; subfolders are not traversed.
- The `process_extraction` function never propagates exceptions to the orchestrator all errors are caught and returned as structured error dicts.
- Run metadata is always uploaded to GCS when at least one file fails; on full success it is uploaded once after all files complete.

**Inputs**
- Google Drive folder named `marketing_upload-folder/{target_folder}` containing CSVs or Google Sheets.
- An `instruction.txt` file inside the target folder with content `file-upload=safe`.
- GCS bucket `marketing-archival-dev` with path `status/{target_folder}.success` (optional dedup gate).

**Outputs**
- Extracted CSV files in GCS at `data/{filename}` inside `marketing-archival-dev`.
- Run metadata JSON at `logs/{target_folder}_metatdata.json` in `marketing-archival-dev`.
- Exit code 0 (success or skipped) or 1 (failure).

## 2. Execution Workflow

1. **Gate:** Check GCS for an existing success marker at `status/{target_folder}.success`. Return 0 if present.
2. **Initialize:** Build a Google Drive API v3 service object.
3. **Resolve:** Locate ROOT_FOLDER (`marketing_upload-folder`) in Drive, then find the date-suffixed target folder within it. Return 1 if either is missing.
4. **Validate:** Verify the `instruction.txt` handshake inside the target folder. List non-instruction files. Return 1 if handshake fails or no valid files exist.
5. **Delegate:** Call `process_extraction` for each file download from Drive (with CSV conversion for Google Sheets) and upload to GCS. Return 1 on first failure.
6. **Persist:** Upload execution metadata JSON to GCS on completion (success or failure).

## 3. Boundaries

| This component **DOES** | This component **DOES NOT** |
| :--- | :--- |
| Download and convert Google Sheets to CSV | Traverse subfolders or nested directory trees |
| Enforce per-folder deduplication via GCS success marker | Delete or archive Drive files after extraction |
| Generate per-run UUID4 execution lineage | Validate CSV schema or column counts |
| Fail-fast on first per-file extraction error | Retry individual file failures independently |
| Upload structured error payloads to GCS on failure | Send email or Slack alerts (delegated to GCP Monitoring) |
| Append Manila-date suffix (`YYYY_MM_DD`) to target folder names | Handle non-CSV, non-Sheets MIME types beyond raw byte download |

## 4. Failure & Severity Model

### Operational Failures (System Level Exit Code 1)
- **Root folder missing:** `marketing_upload-folder` not found or not shared with the Drive SA. No GCS write.
- **Target folder missing:** Date-suffixed folder not found inside root. No GCS write.
- **Handshake failure:** `instruction.txt` missing or does not contain `file-upload=safe`. No GCS write; returns `None`.
- **Empty folder after filtering:** No files other than `instruction.txt` present. No GCS write.
- **Per-file extraction crash:** `extract_file` or `upload_to_gcs` raises an exception. Partial metadata uploaded to GCS with error details. Subsequent files are not processed.

### Functional Findings (Data Level)
- **Google Sheets export:** Server-side CSV conversion via `export_media` may produce different column ordering or encoding than expected. Not validated by this stage.
- **Duplicate source files:** GCS path `data/{filename}` does not include a date prefix; same-named files from different days overwrite unless the source filename includes a date component.
- **Missing success marker hydration:** The orchestrator writes `.success` markers by writing to GCS, not through this stage directly. If that external mechanism fails, the dedup gate drains and re-extraction occurs.
