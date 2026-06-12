# =============================================================================
# UNIT TESTS FOR run_extractor.py and extract_logic.py
# =============================================================================

from unittest.mock import MagicMock

import pytest

from data_extractor.shared.extract_logic import (
    get_target_folder_id,
    get_valid_files,
    process_extraction,
)
from data_extractor.run_extract import orchestrate_extract


@pytest.fixture
def mock_drive():
    """A MagicMock that simulates GoogleDriveService chained API calls."""
    return MagicMock()


# =============================================================================
# TARGET FOLDER ID TESTS
# =============================================================================


def test_root_folder_missing(mock_drive):
    mock_drive.files().list().execute.return_value = {"files": []}

    result = get_target_folder_id("campaigns", mock_drive)

    assert result is None


def test_target_folder_missing(mock_drive):
    mock_drive.files().list().execute.side_effect = [
        {"files": [{"id": "root123"}]},
        {"files": []},
    ]

    result = get_target_folder_id("campaigns", mock_drive)

    assert result is None


def test_get_target_folder_id_success(mock_drive):
    mock_drive.files().list().execute.side_effect = [
        {"files": [{"id": "root123"}]},
        {"files": [{"id": "target456"}]},
    ]

    result = get_target_folder_id("campaigns", mock_drive)

    assert result == "target456"


# =============================================================================
# VALID FILES TESTS
# =============================================================================


def test_handshake_fails_returns_none(mock_drive, monkeypatch):
    monkeypatch.setattr(
        "data_extractor.shared.extract_logic.valid_handshake",
        lambda *a: False,
    )

    result = get_valid_files("folder_id", "campaigns", mock_drive)

    assert result is None


def test_empty_folder_returns_empty_list(mock_drive, monkeypatch):
    monkeypatch.setattr(
        "data_extractor.shared.extract_logic.valid_handshake",
        lambda *a: True,
    )
    mock_drive.files().list().execute.return_value = {"files": []}

    result = get_valid_files("folder_id", "campaigns", mock_drive)

    assert result == []


def test_get_valid_files_success(mock_drive, monkeypatch):
    monkeypatch.setattr(
        "data_extractor.shared.extract_logic.valid_handshake",
        lambda *a: True,
    )
    expected_files = [
        {"id": "f1", "name": "report.csv", "mimeType": "text/csv"},
        {"id": "f2", "name": "data.csv", "mimeType": "text/csv"},
    ]
    mock_drive.files().list().execute.return_value = {"files": expected_files}

    result = get_valid_files("folder_id", "campaigns", mock_drive)

    assert result == expected_files


# =============================================================================
# EXTRACTION PROCESSING TESTS
# =============================================================================


def test_process_extraction_success(monkeypatch):
    monkeypatch.setattr(
        "data_extractor.shared.extract_logic.extract_file",
        lambda *a: b"col1,col2\n1,2",
    )
    monkeypatch.setattr(
        "data_extractor.shared.extract_logic.upload_to_gcs",
        lambda *a, **kw: None,
    )

    ok, details = process_extraction(
        {"id": "123", "name": "data.csv", "mimeType": "text/csv"},
        MagicMock(),
        "data/data.csv",
    )

    assert ok is True
    assert details == {"name": "data.csv", "status": "success"}


def test_process_extraction_fails_on_extract_error(monkeypatch):
    monkeypatch.setattr(
        "data_extractor.shared.extract_logic.extract_file",
        lambda *a: (_ for _ in ()).throw(IOError("Download failed")),
    )
    monkeypatch.setattr(
        "data_extractor.shared.extract_logic.upload_to_gcs",
        lambda *a, **kw: None,
    )

    ok, details = process_extraction(
        {"id": "123", "name": "data.csv", "mimeType": "text/csv"},
        MagicMock(),
        "data/data.csv",
    )

    assert ok is False
    assert details["file_name"] == "data.csv"
    assert details["drive_id"] == "123"
    assert "Download failed" in details["error_message"]


def test_process_extraction_fails_on_upload_error(monkeypatch):
    monkeypatch.setattr(
        "data_extractor.shared.extract_logic.extract_file",
        lambda *a: b"col1\n1",
    )
    monkeypatch.setattr(
        "data_extractor.shared.extract_logic.upload_to_gcs",
        lambda *a, **kw: (_ for _ in ()).throw(RuntimeError("Bucket not found")),
    )

    ok, details = process_extraction(
        {"id": "456", "name": "report.xlsx", "mimeType": "application/octet-stream"},
        MagicMock(),
        "data/report.xlsx",
    )

    assert ok is False
    assert details["file_name"] == "report.xlsx"
    assert details["drive_id"] == "456"
    assert details["error_type"] == "RuntimeError"
    assert "Bucket not found" in details["error_message"]


# =============================================================================
# EXTRACTOR ORCHESTRATION TESTS
# =============================================================================


def test_skip_when_marking_exists(monkeypatch):
    monkeypatch.setattr(
        "data_extractor.run_extract.initialize_gdrive",
        lambda: MagicMock(),
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.check_gcs_marking",
        lambda *a: True,
    )

    exit_code = orchestrate_extract("marketing_campaigns_2026_06_12")

    assert exit_code == 0


def test_returns_1_when_folder_id_not_found(monkeypatch):
    monkeypatch.setattr(
        "data_extractor.run_extract.check_gcs_marking",
        lambda *a: False,
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.initialize_gdrive",
        lambda: MagicMock(),
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.get_target_folder_id",
        lambda *a: None,
    )

    exit_code = orchestrate_extract("missing_folder")

    assert exit_code == 1


def test_returns_1_when_no_valid_files(monkeypatch):
    monkeypatch.setattr(
        "data_extractor.run_extract.check_gcs_marking",
        lambda *a: False,
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.initialize_gdrive",
        lambda: MagicMock(),
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.get_target_folder_id",
        lambda *a: "folder123",
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.get_valid_files",
        lambda *a: None,
    )

    exit_code = orchestrate_extract("empty_folder")

    assert exit_code == 1


def test_returns_1_when_no_valid_files_empty_list(monkeypatch):
    monkeypatch.setattr(
        "data_extractor.run_extract.check_gcs_marking",
        lambda *a: False,
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.initialize_gdrive",
        lambda: MagicMock(),
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.get_target_folder_id",
        lambda *a: "folder123",
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.get_valid_files",
        lambda *a: [],
    )

    exit_code = orchestrate_extract("empty_folder")

    assert exit_code == 1


def test_returns_0_on_successful_extraction(monkeypatch):
    monkeypatch.setattr(
        "data_extractor.run_extract.check_gcs_marking",
        lambda *a: False,
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.initialize_gdrive",
        lambda: MagicMock(),
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.get_target_folder_id",
        lambda *a: "folder456",
    )

    files = [
        {"id": "f1", "name": "data.csv", "mimeType": "text/csv"},
        {"id": "f2", "name": "report.csv", "mimeType": "text/csv"},
    ]
    monkeypatch.setattr(
        "data_extractor.run_extract.get_valid_files",
        lambda *a: files,
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.process_extraction",
        lambda file, drive_api, marketing_bucket_path: (
            True,
            {"name": file["name"], "status": "success"},
        ),
    )

    upload_calls = []
    monkeypatch.setattr(
        "data_extractor.run_extract.upload_to_gcs",
        lambda bucket, path, data: upload_calls.append((bucket, path, data)),
    )

    exit_code = orchestrate_extract("marketing_campaigns")

    assert exit_code == 0
    assert len(upload_calls) == 1
    assert "logs/marketing_campaigns_metatdata.json" in upload_calls[0][1]


def test_returns_1_on_extraction_failure(monkeypatch):
    monkeypatch.setattr(
        "data_extractor.run_extract.check_gcs_marking",
        lambda *a: False,
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.initialize_gdrive",
        lambda: MagicMock(),
    )
    monkeypatch.setattr(
        "data_extractor.run_extract.get_target_folder_id",
        lambda *a: "folder789",
    )

    files = [
        {"id": "f1", "name": "bad.csv", "mimeType": "text/csv"},
        {"id": "f2", "name": "good.csv", "mimeType": "text/csv"},
    ]
    monkeypatch.setattr(
        "data_extractor.run_extract.get_valid_files",
        lambda *a: files,
    )

    def fail_first_then_succeed(file, drive_api, marketing_bucket_path):
        if file["name"] == "bad.csv":
            return False, {
                "file_name": file["name"],
                "drive_id": file["id"],
                "error_type": "ValueError",
                "error_message": "Corrupted file",
            }
        return True, {"name": file["name"], "status": "success"}

    monkeypatch.setattr(
        "data_extractor.run_extract.process_extraction",
        fail_first_then_succeed,
    )

    upload_calls = []
    monkeypatch.setattr(
        "data_extractor.run_extract.upload_to_gcs",
        lambda bucket, path, data: upload_calls.append((bucket, path, data)),
    )

    exit_code = orchestrate_extract("failing_folder")

    assert exit_code == 1
    assert len(upload_calls) == 1
    assert "logs/failing_folder_metatdata.json" in upload_calls[0][1]
    assert '"status": "failed"' in upload_calls[0][2]
    assert "bad.csv" in upload_calls[0][2]
