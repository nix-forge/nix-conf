"""Shared helpers for package updater scripts."""

from __future__ import annotations

import os
import ssl
from pathlib import Path
from typing import Final

HTTPS_CERT_CANDIDATES: Final = (
    os.environ.get("SSL_CERT_FILE"),
    os.environ.get("NIX_SSL_CERT_FILE"),
    "/etc/ssl/cert.pem",
    "/etc/ssl/certs/ca-certificates.crt",
    "/etc/pki/tls/certs/ca-bundle.crt",
    "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt",
)


def https_context() -> ssl.SSLContext:
    """Return an SSL context using the first readable CA bundle.

    Returns:
        SSL context configured with the first readable CA bundle, or the
        default OpenSSL context if none is available.

    """
    for candidate in HTTPS_CERT_CANDIDATES:
        if candidate and Path(candidate).is_file():
            return ssl.create_default_context(cafile=candidate)

    return ssl.create_default_context()


HTTPS_CONTEXT: Final = https_context()
