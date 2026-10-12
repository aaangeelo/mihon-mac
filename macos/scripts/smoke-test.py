#!/usr/bin/env python3
"""Real server integration test using generated comics and isolated data roots.

No user library, accounts, external extension stores, or downloaded manga needed.
Use --keep to retain the first root for native UI verification via MIHON_DATA.
"""
import argparse
import gzip
import json
import shutil
import socket
import struct
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import zlib
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("runtime", type=Path)
parser.add_argument("--keep", action="store_true")
args = parser.parse_args()
runtime = args.runtime.resolve()
roots = []
processes = []
checks = []
engine = Path(tempfile.mkdtemp(prefix="mihon-engine-"))
shutil.copy2(runtime / "Suwayomi-Server.jar", engine / "Suwayomi-Server.jar")
shutil.copy2(runtime / "MihonEngine.class", engine / "MihonEngine.class")

def check(label, condition):
    if not condition:
        raise AssertionError(label)
    checks.append(label)
    print("PASS:", label, flush=True)

def png(width, height, color):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    pixels = b"".join(b"\0" + bytes(color) * width for _ in range(height))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b"")

def request(base, path, method="GET", body=None, form=None, graph=None):
    headers = {}
    if form is not None:
        body = urllib.parse.urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    if graph is not None:
        body = json.dumps({"query": graph}).encode()
        headers["Content-Type"] = "application/json"
    response = urllib.request.urlopen(urllib.request.Request(base + path, body, headers, method=method), timeout=30)
    data = response.read()
    if response.headers.get_content_type() == "application/json":
        return json.loads(data)
    return data

def launch(root):
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0)); port = sock.getsockname()[1]
    java = runtime / "jre/bin/java"
    log = open(root / "smoke-engine.log", "wb")
    command = [str(java), "-Xmx1g", f"-Dsuwayomi.tachidesk.config.server.rootDir={root}", "-Dsuwayomi.tachidesk.config.server.ip=127.0.0.1", f"-Dsuwayomi.tachidesk.config.server.port={port}", "-Dsuwayomi.tachidesk.config.server.initialOpenInBrowserEnabled=false", "-Dsuwayomi.tachidesk.config.server.systemTrayEnabled=false", "-Dsuwayomi.tachidesk.config.server.webUIChannel=BUNDLED", "-Dsuwayomi.tachidesk.config.server.webUIUpdateCheckInterval=0", "-cp", str(engine / "Suwayomi-Server.jar") + ":" + str(engine), "MihonEngine"]
    process = subprocess.Popen(command, stdout=log, stderr=log, cwd=engine)
    processes.append((process, log))
    base = f"http://127.0.0.1:{port}"
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError((root / "smoke-engine.log").read_text()[-5000:])
        try:
            request(base, "/api/v1/category")
            return base
        except (OSError, urllib.error.URLError):
            time.sleep(0.5)
    raise RuntimeError("Server startup timed out: " + str(root))

def stop(process, log):
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill(); process.wait()
    log.close()

try:
    root = Path(tempfile.mkdtemp(prefix="mihon-mac-qa-")); roots.append(root)
    series = root / "local" / "Native Reader QA"
    series.mkdir(parents=True)
    with zipfile.ZipFile(series / "Chapter 1.cbz", "w") as archive:
        for i, color in enumerate([(74, 84, 142), (219, 186, 135), (77, 128, 116)]):
            archive.writestr(f"{i + 1:03}.png", png(700, 1000, color))
    base = launch(root)
    check("Fresh isolated engine starts", True)
    check("Bundled local control panel is available", b"<html" in request(base, "/").lower())
    sources = request(base, "/api/v1/source/list")
    check("Local source available", any(s["id"] == "0" for s in sources))
    browse = request(base, "/api/v1/source/0/popular/1")
    manga = next(m for m in browse["mangaList"] if m["title"] == "Native Reader QA")
    mid = manga["id"]
    request(base, f"/api/v1/manga/{mid}/library")
    request(base, f"/api/v1/manga/{mid}/full?onlineFetch=true")
    chapters = request(base, f"/api/v1/manga/{mid}/chapters?onlineFetch=true")
    check("CBZ imports as a chapter", len(chapters) == 1)
    chapter = request(base, f"/api/v1/manga/{mid}/chapter/{chapters[0]['index']}")
    check("Reader has three pages", chapter["pageCount"] == 3)
    image = request(base, f"/api/v1/manga/{mid}/chapter/{chapter['index']}/page/0")
    check("Actual page image served", image.startswith(b"\x89PNG"))
    request(base, f"/api/v1/manga/{mid}/chapter/{chapter['index']}", "PATCH", form={"lastPageRead": "2", "read": "true", "bookmarked": "true"})
    saved = request(base, f"/api/v1/manga/{mid}/chapters")[0]
    check("Progress, read state and bookmark persist", saved["lastPageRead"] == 2 and saved["read"] and saved["bookmarked"])
    library = request(base, "/api/v1/category/0")
    check("Library and partial/read history totals reconcile", len(library) == 1 and library[0]["unreadCount"] == 0 and library[0]["lastReadAt"] > 0)
    request(base, "/api/v1/category", "POST", form={"name": "QA Category"})
    category = next(c for c in request(base, "/api/v1/category") if c["name"] == "QA Category")
    request(base, f"/api/v1/manga/{mid}/category/{category['id']}")
    check("Native category API maps title", request(base, f"/api/v1/category/{category['id']}")[0]["id"] == mid)
    downloads = request(base, "/api/graphql", "POST", graph="{ downloadStatus { state queue { state progress tries position manga { id title } chapter { id name mangaId sourceOrder } } } }")
    check("Downloads native query matches live schema", "errors" not in downloads and downloads["data"]["downloadStatus"]["queue"] == [])
    stores = request(base, "/api/graphql", "POST", graph="{ extensionStores { nodes { indexUrl } } }")
    check("No preconfigured third-party repositories", "errors" not in stores and stores["data"]["extensionStores"]["nodes"] == [])
    check("Six tracker services exposed", len(request(base, "/api/v1/track/list")) == 6)
    request(base, "/api/v1/update/summary")
    request(base, "/api/v1/update/recentChapters/0")
    check("Updates endpoints work", True)
    backup = request(base, "/api/v1/backup/export")
    check("Backup is a nonempty gzip protobuf", backup[:2] == b"\x1f\x8b" and len(gzip.decompress(backup)) > 0)
    validation = request(base, "/api/v1/backup/validate", "POST", body=backup)
    check("Exported backup validates", isinstance(validation, dict))
    (root / "qa-backup.tachibk").write_bytes(backup)
    stop(*processes.pop())
    base = launch(root)
    check("Relaunch preserves reading state", request(base, f"/api/v1/manga/{mid}/chapters")[0]["read"])
    stop(*processes.pop())
    restored = Path(tempfile.mkdtemp(prefix="mihon-mac-restore-qa-")); roots.append(restored)
    # Backups intentionally exclude comic files; copy the same content separately.
    shutil.copytree(root / "local", restored / "local")
    restored_base = launch(restored)
    report = request(restored_base, "/api/v1/backup/import", "POST", body=backup)
    restored_cats = request(restored_base, "/api/v1/category")
    cat = next(c for c in restored_cats if c["name"] == "QA Category")
    restored_manga = request(restored_base, f"/api/v1/category/{cat['id']}")[0]
    restored_chapter = request(restored_base, f"/api/v1/manga/{restored_manga['id']}/chapters")[0]
    check("Backup restores into a second fresh database", restored_manga["title"] == manga["title"] and restored_chapter["read"] and restored_chapter["bookmarked"] and restored_chapter["lastPageRead"] == 2)
    result = {"checks": checks, "fixtureRoot": str(root) if args.keep else None, "restoreReport": report}
    print(json.dumps(result, indent=2), flush=True)
finally:
    for process, log in processes:
        stop(process, log)
    for index, root in enumerate(roots):
        if not (args.keep and index == 0):
            shutil.rmtree(root)
    shutil.rmtree(engine)
