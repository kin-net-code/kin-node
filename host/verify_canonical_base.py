"""Verify the exact local VirtualBox base admitted for Kin Node builds.

The root-owned receipt is produced by the separate image-sanitization process. It
binds a user-owned local Vagrant box tree to Canonical's signed, release-pinned OVA
and to explicit no-credential/no-runtime-data assertions. A box name or a receipt
inside the mutable provider tree is not provenance.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import sys
from pathlib import Path
from typing import Any

SCHEMA = "kin-canonical-base-provenance/0.1"
BOX_NAME = "kin/sanitized-ubuntu-26.04"
BOX_PROVIDER = "virtualbox"
RECEIPT_PATH = Path("/var/lib/kin-base-images/kin-sanitized-ubuntu-26.04.json")
SOURCE = {
    "publisher": "Canonical",
    "release": "20260823",
    "artifact": "ubuntu-26.04-server-cloudimg-amd64.ova",
    "url": (
        "https://cloud-images.ubuntu.com/releases/resolute/release-20260823/"
        "ubuntu-26.04-server-cloudimg-amd64.ova"
    ),
    "sha256": "39ffcd0f7cfab17c266d8c7e13c66f034068702b01784e502b3aadd7ebd0b485",
    "manifestUrl": (
        "https://cloud-images.ubuntu.com/releases/resolute/release-20260823/"
        "SHA256SUMS"
    ),
    "manifestSignatureUrl": (
        "https://cloud-images.ubuntu.com/releases/resolute/release-20260823/"
        "SHA256SUMS.gpg"
    ),
    "manifestSignatureVerified": True,
}
SANITIZATION = {
    "preparedFromCanonicalArtifact": True,
    "credentialsEverPresent": False,
    "kinRuntimeDataEverPresent": False,
}
VERSION = re.compile(r"^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$")
DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")


class BaseImageError(RuntimeError):
    pass


def _frame(hasher: Any, value: bytes) -> None:
    hasher.update(len(value).to_bytes(8, "big"))
    hasher.update(value)


def tree_digest(root: Path, *, expected_uid: int | None = None) -> str:
    """Hash names, types, modes, sizes, and bytes beneath a provider directory."""
    try:
        root_metadata = root.lstat()
    except FileNotFoundError:
        raise BaseImageError("BASE_PROVIDER_DIRECTORY_ABSENT") from None
    if (not stat.S_ISDIR(root_metadata.st_mode) or root.is_symlink() or
            (expected_uid is not None and root_metadata.st_uid != expected_uid) or
            root_metadata.st_mode & 0o022):
        raise BaseImageError("BASE_PROVIDER_DIRECTORY_UNSAFE")
    hasher = hashlib.sha256()
    members = sorted(root.rglob("*"), key=lambda path: path.relative_to(root).as_posix())
    for path in members:
        relative = path.relative_to(root).as_posix()
        try:
            encoded_name = relative.encode("utf-8", errors="strict")
        except UnicodeEncodeError:
            raise BaseImageError("BASE_MEMBER_NAME_INVALID") from None
        metadata = path.lstat()
        if (expected_uid is not None and metadata.st_uid != expected_uid) or \
                metadata.st_mode & 0o022:
            raise BaseImageError(f"BASE_MEMBER_PERMISSIONS_UNSAFE:{relative}")
        if stat.S_ISDIR(metadata.st_mode):
            kind = b"directory"
            content = b""
            size = b"0"
        elif stat.S_ISREG(metadata.st_mode):
            kind = b"file"
            content_hasher = hashlib.sha256()
            with path.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    content_hasher.update(block)
            content = content_hasher.hexdigest().encode("ascii")
            size = str(metadata.st_size).encode("ascii")
        else:
            raise BaseImageError(f"BASE_MEMBER_TYPE_UNSAFE:{relative}")
        for field in (
                kind, encoded_name, oct(stat.S_IMODE(metadata.st_mode)).encode("ascii"),
                size, content):
            _frame(hasher, field)
    return "sha256:" + hasher.hexdigest()


def load_receipt(path: Path, *, expected_uid: int = 0) -> dict[str, Any]:
    try:
        parent = path.parent.lstat()
    except FileNotFoundError:
        raise BaseImageError("BASE_PROVENANCE_DIRECTORY_ABSENT") from None
    if (not stat.S_ISDIR(parent.st_mode) or path.parent.is_symlink() or
            parent.st_uid != expected_uid or parent.st_mode & 0o022):
        raise BaseImageError("BASE_PROVENANCE_DIRECTORY_UNSAFE")
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        raise BaseImageError("BASE_PROVENANCE_RECEIPT_ABSENT") from None
    if (not stat.S_ISREG(metadata.st_mode) or path.is_symlink() or
            metadata.st_size > 16 * 1024 or metadata.st_mode & 0o022 or
            (expected_uid is not None and metadata.st_uid != expected_uid)):
        raise BaseImageError("BASE_PROVENANCE_RECEIPT_UNSAFE")
    try:
        value = json.loads(path.read_bytes())
    except (json.JSONDecodeError, UnicodeDecodeError):
        raise BaseImageError("BASE_PROVENANCE_RECEIPT_INVALID") from None
    if not isinstance(value, dict):
        raise BaseImageError("BASE_PROVENANCE_RECEIPT_INVALID")
    return value


def verify(root: Path, version: str, receipt_path: Path = RECEIPT_PATH, *,
           expected_uid: int | None = None, receipt_expected_uid: int = 0) -> str:
    if not VERSION.fullmatch(version):
        raise BaseImageError("BASE_VERSION_INVALID")
    receipt = load_receipt(receipt_path, expected_uid=receipt_expected_uid)
    if set(receipt) != {
            "schema", "boxName", "boxProvider", "boxVersion", "boxTreeSha256",
            "source", "sanitization"}:
        raise BaseImageError("BASE_PROVENANCE_RECEIPT_FIELDS_INVALID")
    if (receipt.get("schema") != SCHEMA or receipt.get("boxName") != BOX_NAME or
            receipt.get("boxProvider") != BOX_PROVIDER or
            receipt.get("boxVersion") != version or receipt.get("source") != SOURCE or
            receipt.get("sanitization") != SANITIZATION or
            not isinstance(receipt.get("boxTreeSha256"), str) or
            not DIGEST.fullmatch(receipt["boxTreeSha256"])):
        raise BaseImageError("BASE_PROVENANCE_RECEIPT_CLAIM_INVALID")
    observed = tree_digest(root, expected_uid=expected_uid)
    if observed != receipt["boxTreeSha256"]:
        raise BaseImageError("BASE_TREE_DIGEST_MISMATCH")
    return observed


def main() -> int:
    if len(sys.argv) != 4:
        print("FAIL  usage: verify_canonical_base.py PROVIDER_DIRECTORY BOX_VERSION ROOT_RECEIPT",
              file=sys.stderr)
        return 2
    try:
        digest = verify(Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]),
                        expected_uid=os.getuid(), receipt_expected_uid=0)
    except (BaseImageError, OSError, ValueError) as error:
        print(f"FAIL  Canonical base provenance: {error}", file=sys.stderr)
        return 1
    print("PASS  Canonical base provenance verified: "
          f"release {SOURCE['release']}, tree {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
