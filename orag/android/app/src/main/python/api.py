from pipeline import init, chat_direct
import threading

_initialized = False
_init_lock = threading.Lock()

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
    try:
        ensure_ready()

        ok, response = chat_direct(
            question=query,
            history=[],
            summary=""
        )

        return response if ok else f"ERROR: {response}"

    except Exception as e:
        return f"ERROR: {str(e)}"