"""
Convert rag_vector.db from the old flutter_gemma_rag_sqlite 1.0.x schema
(regular `documents` table) to the new 1.1.0 schema (vec0 virtual table
`vec_documents`), using the prebuilt libvec0.dylib from the pub cache.

Usage:
    python scripts/convert_rag_db.py
"""

import sqlite3
import struct
import os
from pathlib import Path

# Paths
PUB_CACHE_VEC0 = Path.home() / ".pub-cache/hosted/pub.dev/flutter_gemma_rag_sqlite-1.1.0/native/sqlite_vec/prebuilt/macos_arm64/libvec0.dylib"
OLD_DB = Path("assets/manuals/rag_vector.db")
NEW_DB = Path("assets/manuals/rag_vector_new.db")

def main():
    assert OLD_DB.exists(), f"Source not found: {OLD_DB}"
    assert PUB_CACHE_VEC0.exists(), f"libvec0.dylib not found: {PUB_CACHE_VEC0}"

    print(f"Reading source: {OLD_DB}")
    src = sqlite3.connect(str(OLD_DB))
    rows = src.execute(
        "SELECT id, content, embedding, metadata FROM documents ORDER BY rowid"
    ).fetchall()
    src.close()
    print(f"  {len(rows)} rows loaded")

    # Detect embedding dimension from first row
    first_blob = rows[0][2]
    dim = len(first_blob) // 4  # float32 = 4 bytes
    print(f"  Embedding dimension: {dim}")

    if NEW_DB.exists():
        NEW_DB.unlink()

    print(f"Creating new DB: {NEW_DB}")
    dst = sqlite3.connect(str(NEW_DB))
    dst.enable_load_extension(True)
    dst.load_extension(str(PUB_CACHE_VEC0))
    dst.enable_load_extension(False)

    # Create vec_documents virtual table — same DDL as flutter_gemma_rag_sqlite 1.1.0
    dst.execute(f"""
        CREATE VIRTUAL TABLE vec_documents USING vec0(
          id TEXT PRIMARY KEY,
          embedding float[{dim}] distance_metric=cosine,
          +content TEXT,
          +metadata TEXT
        )
    """)
    dst.commit()
    print(f"  vec_documents table created (dim={dim}, cosine)")

    print("  Inserting rows…")
    batch = []
    for i, (row_id, content, embedding_blob, metadata) in enumerate(rows):
        # Convert BLOB bytes back to list of float32
        floats = list(struct.unpack(f"{dim}f", embedding_blob))
        # vec0 expects embedding as serialised float32 blob (same wire format)
        batch.append((row_id, embedding_blob, content, metadata))
        if len(batch) == 500 or i == len(rows) - 1:
            dst.executemany(
                "INSERT INTO vec_documents(id, embedding, content, metadata) VALUES (?,?,?,?)",
                batch,
            )
            dst.commit()
            print(f"    {i + 1} / {len(rows)}")
            batch = []

    # Verify
    count = dst.execute("SELECT COUNT(*) FROM vec_documents").fetchone()[0]
    print(f"  Inserted: {count} rows")
    dst.close()

    # Replace old DB with new one
    OLD_DB.unlink()
    NEW_DB.rename(OLD_DB)
    size_mb = OLD_DB.stat().st_size / 1_048_576
    print(f"\nDone! {OLD_DB} ({size_mb:.1f} MB, {count} rows, dim={dim})")

if __name__ == "__main__":
    main()
