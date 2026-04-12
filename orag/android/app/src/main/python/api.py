from pipeline import init, chat_direct, get_bootstrap_event, is_model_loaded
from pipeline import register_auto_download_callbacks
from downloader import set_model_dir, auto_download_default, model_dest_path, QWEN_MODEL
from runtime.bootstrap import BootstrapState
import threading
import json

_initialized = False
_init_lock = threading.Lock()
_is_generating = False
_stop_flag = False
_conversation_history = []
MAX_TURNS = 5

# ---- Progress callback holder (set from Kotlin) ----
_progress_callback = None
_progress_lock = threading.Lock()


def _set_progress_callback(cb):
    global _progress_callback
    with _progress_lock:
        _progress_callback = cb


def _emit_progress(state, progress, message):
    """Send a progress event to Flutter via the Kotlin callback."""
    with _progress_lock:
        cb = _progress_callback
    if cb is not None:
        try:
            data = json.dumps({
                "state": state,
                "progress": max(0.0, min(1.0, progress)),
                "message": str(message),
            })
            cb.invoke(data)
        except Exception as e:
            print(f"[API] progress callback error: {e}")


def trim_history():
    global _conversation_history
    if len(_conversation_history) > MAX_TURNS:
        _conversation_history = _conversation_history[-MAX_TURNS:]


def clear_memory():
    global _conversation_history
    _conversation_history = []


def stop_generation():
    global _stop_flag
    _stop_flag = True


def wait_for_server():
    import urllib.request
    import time
    for _ in range(10):
        try:
            r = urllib.request.urlopen("http://127.0.0.1:8080/health", timeout=2)
            if r.getcode() == 200:
                return True
        except Exception:
            pass
        time.sleep(1)
    raise RuntimeError("Server not ready")


def ensure_ready(model_path=None):
    global _initialized
    if _initialized:
        return
    with _init_lock:
        if not _initialized:
            init(model_path)   # this will now BLOCK until models are ready
            _initialized = True


def init_with_path(model_path):
    ensure_ready(model_path)


def init_with_progress(model_path, progress_callback):
    """Initialize with real-time progress events pushed to Flutter.

    progress_callback is a Kotlin method reference called via .invoke(jsonString).
    Events have the shape: {"state": "downloading|loading|ready|error", "progress": 0.0-1.0, "message": "..."}
    """
    global _initialized

    if _initialized:
        _emit_progress("ready", 1.0, "AI engine ready.")
        return

    _set_progress_callback(progress_callback)

    with _init_lock:
        if _initialized:
            _emit_progress("ready", 1.0, "AI engine ready.")
            return

        try:
            # Step 0: Setup
            _emit_progress("downloading", 0.0, "Preparing…")

            if model_path:
                set_model_dir(model_path)

            from storage import init_db
            from pipeline import retriever, runtime
            init_db()
            retriever.reload()

            # Step 1: Download models (with progress)
            download_done = threading.Event()
            download_error = [None]

            def on_download_progress(frac, text):
                _emit_progress("downloading", frac, text)

            def on_download_done(success, message):
                if not success:
                    download_error[0] = message
                download_done.set()

            auto_download_default(
                on_progress=on_download_progress,
                on_done=on_download_done,
            )

            # Wait for download to complete
            download_done.wait(timeout=600)

            if download_error[0]:
                _emit_progress("error", 1.0, download_error[0])
                return

            # Step 2: Load model (with progress)
            qwen_path = model_dest_path(QWEN_MODEL["filename"])

            if not runtime.is_loaded():
                _emit_progress("loading", 0.05, "Starting AI engine…")

                def on_load_progress(frac, text):
                    _emit_progress("loading", frac, text)

                runtime.load(qwen_path, on_progress=on_load_progress)

            _initialized = True
            _emit_progress("ready", 1.0, "AI engine ready!")

        except Exception as e:
            _emit_progress("error", 1.0, f"Init failed: {e}")
            raise


def get_status():
    """Return current bootstrap state as a dict for one-shot polling."""
    if _initialized:
        return {"state": "ready", "progress": 1.0, "message": "AI engine ready."}

    try:
        evt = get_bootstrap_event()
        state_map = {
            BootstrapState.IDLE: "idle",
            BootstrapState.DOWNLOADING: "downloading",
            BootstrapState.READY: "ready",
            BootstrapState.ERROR: "error",
        }
        return {
            "state": state_map.get(evt.state, "idle"),
            "progress": evt.progress,
            "message": evt.message,
        }
    except Exception:
        return {"state": "idle", "progress": 0.0, "message": ""}


def chat(query):
    global _is_generating, _stop_flag

    if _is_generating:
        return "Please wait, processing previous request..."

    _is_generating = True
    _stop_flag = False
    print("[CHAT] Request started")
    
    try:
        ensure_ready()
        wait_for_server()
        trim_history()

        ok, response = chat_direct(
            question=query,
            history=_conversation_history,
            summary=""
        )

        if ok:
            _conversation_history.append((query, response))

        print("[CHAT] Response received")
        return response if ok else f"ERROR: {response}"

    except Exception as e:
        return f"ERROR: {str(e)}"
    finally:
        _is_generating = False


def chat_stream(query, token_callback):
    """Streaming chat — calls token_callback for each generated token.

    ``token_callback`` is a Kotlin method reference passed via Chaquopy.
    On the Python side it is a ``PyObject`` that we call with ``.invoke(token)``
    (Chaquopy's standard mechanism for calling JVM method references).

    Returns the full response string when generation finishes.
    """
    global _is_generating, _stop_flag

    if _is_generating:
        return "Please wait, processing previous request..."

    _is_generating = True
    _stop_flag = False
    print("[CHAT-STREAM] Request started")
    
    try:
        ensure_ready()
        wait_for_server()

        def _on_token(token):
            try:
                # Chaquopy method references are called via .invoke()
                token_callback.invoke(token)
            except Exception as e:
                print(f"[CHAT-STREAM] callback error: {e}")

        trim_history()
        ok, response = chat_direct(
            question=query,
            history=_conversation_history,
            summary="",
            stream_cb=_on_token,
        )

        if ok:
            _conversation_history.append((query, response))

        print("[CHAT-STREAM] Response received")
        return response if ok else f"ERROR: {response}"

    except Exception as e:
        return f"ERROR: {str(e)}"
    finally:
        _is_generating = False