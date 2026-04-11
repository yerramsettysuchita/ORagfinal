from pipeline import init, chat_direct
import threading

_initialized = False
_init_lock = threading.Lock()
_is_generating = False
_stop_flag = False

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

        ok, response = chat_direct(
            question=query,
            history=[],
            summary=""
        )

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

        ok, response = chat_direct(
            question=query,
            history=[],
            summary="",
            stream_cb=_on_token,
        )

        print("[CHAT-STREAM] Response received")
        return response if ok else f"ERROR: {response}"

    except Exception as e:
        return f"ERROR: {str(e)}"
    finally:
        _is_generating = False