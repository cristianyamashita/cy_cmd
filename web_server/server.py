#!/usr/bin/env python3
"""Serve a local directory over HTTP."""

from __future__ import annotations

import argparse
import os
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class NoCacheRequestHandler(SimpleHTTPRequestHandler):
    """Static file handler that disables browser caching for local testing."""

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def do_GET(self) -> None:
        self._strip_conditional_headers()
        super().do_GET()

    def do_HEAD(self) -> None:
        self._strip_conditional_headers()
        super().do_HEAD()

    def _strip_conditional_headers(self) -> None:
        for header in ("If-Modified-Since", "If-None-Match"):
            if header in self.headers:
                del self.headers[header]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Serve a local directory over HTTP.")
    parser.add_argument("path", help="Directory to serve")
    parser.add_argument(
        "-p",
        "--port",
        type=int,
        default=8000,
        help="Port to listen on (default: 8000)",
    )
    parser.add_argument(
        "-b",
        "--bind",
        default="127.0.0.1",
        help="Address to bind (default: 127.0.0.1)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(os.path.expanduser(args.path)).resolve()

    if not root.exists():
        print(f"Path not found: {root}", file=sys.stderr)
        return 1
    if not root.is_dir():
        print(f"Not a directory: {root}", file=sys.stderr)
        return 1

    handler = partial(NoCacheRequestHandler, directory=str(root))
    server = ThreadingHTTPServer((args.bind, args.port), handler)
    print(f"Serving {root}")
    print(f"URL: http://{args.bind}:{args.port}/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
