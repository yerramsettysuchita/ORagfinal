"""
pipeline.py - Orchestrates document ingest, retrieval and generation.
"""
from __future__ import annotations

import os
import time
from pathlib import Path
from typing import Callable, Optional


from config import QWEN_SERVER_PORT
from runtime.bootstrap import BootstrapCoordinator
from runtime.model_runtime import LlamaModelRuntime, ModelRuntime
from chunker import process_document
from downloader import NOMIC_MODEL, QWEN_MODEL, auto_download_default, model_dest_path, auto_download_default_sync, set_model_dir
from llm import build_direct_prompt, build_rag_prompt
from retriever import HybridRetriever
from storage import (
    delete_document as storage_delete_document,
    get_conn,
    init_db,
    insert_chunks,
    insert_document,
    list_documents as storage_list_documents,
    update_doc_chunk_count,
)


# Module-level retriever/runtime (shared across the whole app)
retriever = HybridRetriever(alpha=0.5)
runtime: ModelRuntime = LlamaModelRuntime()
bootstrap = BootstrapCoordinator()


def _service_qwen_ready(wait_seconds: float = 0.0, per_try_timeout: float = 0.35) -> bool:
    import urllib.request

    attempts = max(1, int(wait_seconds / 0.5))
    for i in range(attempts):
        try:
            with urllib.request.urlopen(
                f"http://127.0.0.1:{QWEN_SERVER_PORT}/health",
                timeout=per_try_timeout,
            ) as r:
                if r.status == 200:
                    return True
        except Exception:
            pass
        if i < attempts - 1:
            time.sleep(0.5)
    return False


def register_auto_download_callbacks(
    on_progress: Optional[Callable[[float, str], None]],
    on_done: Optional[Callable[[bool, str], None]],
) -> None:
    """
    Register UI callbacks for model bootstrap lifecycle.
    """
    bootstrap.register_callbacks(on_progress=on_progress, on_done=on_done)

    # Fast-path: if model already loaded or service already healthy, mark ready.
    if runtime.is_loaded():
        bootstrap.emit_ready("Models ready: Qwen + Nomic")
        return

    if _service_qwen_ready(wait_seconds=0.0):
        qwen_path = model_dest_path(QWEN_MODEL["filename"])
        try:
            runtime.connect_external_server(qwen_path)
            bootstrap.emit_ready("Models ready: Qwen + Nomic (service)")
        except Exception:
            pass


def init(model_path: Optional[str] = None) -> None:
    print("[INIT] Starting initialization...")

    if model_path:
        set_model_dir(model_path)

    init_db()
    retriever.reload()

    # Step 1: Ensure models are downloaded
    auto_download_default_sync()

    # Step 2: Load Qwen model into runtime
    qwen_path = model_dest_path("qwen2.5-1.5b-instruct-compressed.gguf")

    print("[INIT] Loading model via runtime...")

    try:
        runtime.load(qwen_path)
        print("[INIT] Model loaded successfully.")
    except Exception as e:
        print(f"[INIT] Model loading failed: {e}")
        raise
        
    # Step 3: Ensure Nomic embedding server is started (so RAG works on app restarts)
    if isinstance(runtime, LlamaModelRuntime):
        nomic_path = model_dest_path(NOMIC_MODEL["filename"])
        if os.path.isfile(nomic_path):
            print("[INIT] Starting Nomic embedding server...")
            runtime.start_nomic_server_if_needed(nomic_path)


def _start_auto_download() -> None:
    """Ensure Qwen + Nomic are on disk, then load/connect Qwen."""

    def _progress(frac: float, text: str) -> None:
        bootstrap.emit_downloading(frac, text)

    def _done(success: bool, message: str) -> None:
        qwen_path = model_dest_path(QWEN_MODEL["filename"])

        if not success:
            bootstrap.emit_error(message)
            return

        if runtime.is_loaded():
            bootstrap.emit_ready("Models ready: Qwen + Nomic")
            return

        # Prefer the service-owned Qwen server if it is up.
        if _service_qwen_ready(wait_seconds=12.0):
            try:
                runtime.connect_external_server(qwen_path)
                bootstrap.emit_ready("Models ready: Qwen + Nomic")
                return
            except Exception:
                pass

        # Fallback: load/connect from app process.
        ok, msg = load_model(qwen_path, on_progress=_progress)
        if ok:
            bootstrap.emit_ready(msg)
        else:
            bootstrap.emit_error(msg)

    auto_download_default(on_progress=_progress, on_done=_done)


def ingest_document(
    file_path: str,
    on_done: Optional[Callable[[bool, str], None]] = None,
) -> tuple[bool, str]:
    """
    Ingest a .txt or .pdf file synchronously.
    Starts Nomic server lazily on first call.

    The document row is only updated with the chunk count AFTER all
    chunks are fully processed and inserted, so the UI never shows
    a document with 0 chunks while processing is in-flight.
    """
    try:
        # Resolve content:// URI to a real file path (Android)
        from chunker import resolve_uri, extract_text, chunk_text, tokenise, compute_tfidf_vecs
        resolved = resolve_uri(file_path)
        name = Path(resolved).name
        print(f"[INGEST] Starting: {name} ({resolved})")

        # Start Nomic server lazily (needed for embeddings)
        nomic_path = model_dest_path(NOMIC_MODEL["filename"])
        if os.path.isfile(nomic_path) and isinstance(runtime, LlamaModelRuntime):
            runtime.start_nomic_server_if_needed(nomic_path)

        # Step 1: Extract text
        raw_text = extract_text(resolved)
        if not raw_text or not raw_text.strip():
            result = (False, f"No text could be extracted from '{name}'")
            if on_done:
                on_done(*result)
            return result
        print(f"[INGEST] Extracted {len(raw_text)} chars")

        # Step 2: Chunk + compute TF-IDF vectors
        raw_chunks = chunk_text(raw_text)
        if not raw_chunks:
            result = (False, f"Document '{name}' produced 0 chunks")
            if on_done:
                on_done(*result)
            return result

        token_lists = [tokenise(c) for c in raw_chunks]
        tfidf_vecs, _ = compute_tfidf_vecs(token_lists)
        chunks = []
        for idx, (text, tokens, vec) in enumerate(
            zip(raw_chunks, token_lists, tfidf_vecs)
        ):
            chunks.append({
                "chunk_idx": idx,
                "text": text,
                "tokens": tokens,
                "tfidf_vec": vec,
            })
        print(f"[INGEST] {len(chunks)} chunks ready")

        # Step 3: Insert document + chunks atomically
        doc_id = insert_document(name, resolved)
        insert_chunks(doc_id, chunks)
        update_doc_chunk_count(doc_id, len(chunks))
        print(f"[INGEST] Saved {len(chunks)} chunks for doc_id={doc_id}")

        # Step 4: Reload retriever so new chunks are queryable
        retriever.reload()
        print(f"[INGEST] Retriever reloaded")

        result = (True, f"Ingested '{name}' — {len(chunks)} chunks")
    except Exception as exc:
        import traceback
        traceback.print_exc()
        result = (False, f"Error: {exc}")

    if on_done:
        on_done(*result)
    return result


def load_model(
    model_path: str,
    on_progress: Optional[Callable[[float, str], None]] = None,
    on_done: Optional[Callable[[bool, str], None]] = None,
) -> tuple[bool, str]:
    """Load a GGUF model synchronously."""
    try:
        runtime.load(model_path, on_progress=on_progress)
        result = (True, f"Model loaded: {Path(model_path).name}")
    except Exception as exc:
        result = (False, f"Failed to load model: {exc}")

    if on_done:
        on_done(*result)
    return result


def get_available_models() -> list[str]:
    if isinstance(runtime, LlamaModelRuntime):
        return runtime.available_models()
    return []


def clear_all_documents() -> None:
    """Delete all ingested documents + chunks and reset the in-memory retriever."""
    with get_conn() as conn:
        conn.execute("DELETE FROM chunks")
        conn.execute("DELETE FROM documents")
    retriever.reload()


def is_model_loaded() -> bool:
    return runtime.is_loaded()


def get_bootstrap_event():
    """Return the latest bootstrap state snapshot for UI surfaces."""
    return bootstrap.event()


def list_documents() -> list[dict]:
    """List ingested documents sorted by most recent first.

    Safe during very early startup before init() has run.
    """
    try:
        init_db()
        return storage_list_documents()
    except Exception:
        return []


def delete_document_by_id(doc_id: int) -> None:
    """Delete a document and refresh the in-memory retriever index."""
    try:
        init_db()
        storage_delete_document(doc_id)
    finally:
        retriever.reload()


def chat_direct(
    question: str,
    history: list | None = None,
    summary: str = "",
    stream_cb: Optional[Callable[[str], None]] = None,
    on_done: Optional[Callable[[bool, str], None]] = None,
) -> tuple[bool, str]:
    """
    Chat directly with the LLM (no retrieval).
    history: last 3 verbatim (user, assistant) turns.
    summary: compressed plain-text summary of older turns.
    """
    try:
        if not runtime.is_loaded():
            result = (False, "No LLM model loaded. Please load a GGUF model first.")
        else:
            prompt = build_direct_prompt(question, history, summary)
            
            # Simple debug logger to show that generation is actually happening
            def _debug_stream(token: str):
                import sys
                sys.stdout.write(token)
                sys.stdout.flush()
                if stream_cb:
                    stream_cb(token)
                    
            print("[DEBUG] Generation started...")
            answer = runtime.generate(prompt, stream_cb=_debug_stream).strip()
            print("\n[DEBUG] Generation finished.")
            result = (True, answer)
    except Exception as exc:
        result = (False, f"Error during inference: {exc}")

    if on_done:
        on_done(*result)
    return result


def ask(
    question: str,
    stream_cb: Optional[Callable[[str], None]] = None,
    on_done: Optional[Callable[[bool, str], None]] = None,
) -> tuple[bool, str, list]:
    """
    Run a RAG query synchronously.
    Retrieves top-2 chunks to fit mobile context budget.
    Returns (success, answer, sources) where sources is a list of dicts:
      [{"doc_name": "...", "chunk_text": "...", "score": 0.85}, ...]
    """
    sources = []
    try:
        if retriever.is_empty():
            result = (False, "No documents ingested yet.", [])
        elif not runtime.is_loaded():
            result = (False, "No LLM model loaded. Please load a GGUF model first.", [])
        else:
            print(f"[RAG] Query: {question[:100]}")
            results = retriever.query(question, top_k=2)
            if not results:
                print("[RAG] No relevant context found")
                result = (False, "No relevant context found.", [])
            else:
                context_chunks = [text for text, _, _ in results]
                for i, (text, score, doc_id) in enumerate(results):
                    print(f"[RAG] Chunk {i}: score={score:.3f}, doc_id={doc_id}, text={text[:80]}...")

                prompt = build_rag_prompt(context_chunks, question)
                print(f"[RAG] Prompt length: {len(prompt)} chars")

                # Build source metadata
                doc_name_cache = {}
                try:
                    docs = storage_list_documents()
                    for d in docs:
                        doc_name_cache[d["id"]] = d["name"]
                except Exception:
                    pass

                seen_doc_names = set()
                for text, score, doc_id in results:
                    doc_name = doc_name_cache.get(doc_id, f"Document #{doc_id}")
                    if doc_name in seen_doc_names:
                        continue
                    seen_doc_names.add(doc_name)
                    sources.append({
                        "doc_name": doc_name,
                        "chunk_text": text[:200],  # Preview only
                        "score": round(score, 3),
                    })

                # Debug stream wrapper
                def _debug_stream(token: str):
                    import sys
                    sys.stdout.write(token)
                    sys.stdout.flush()
                    if stream_cb:
                        stream_cb(token)

                print("[RAG] Generation started...")
                answer = runtime.generate(prompt, stream_cb=_debug_stream).strip()
                print(f"\n[RAG] Generation finished. Answer length: {len(answer)}")
                result = (True, answer, sources)
    except Exception as exc:
        import traceback
        traceback.print_exc()
        result = (False, f"Error during inference: {exc}", [])

    if on_done:
        on_done(result[0], result[1])
    return result
