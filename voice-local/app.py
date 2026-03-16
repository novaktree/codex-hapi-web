import base64
import os
import tempfile
from pathlib import Path

from flask import Flask, jsonify, request
from faster_whisper import WhisperModel


MODEL_SIZE = os.getenv("WHISPER_MODEL_SIZE", "small")
DEVICE = os.getenv("WHISPER_DEVICE", "auto")
COMPUTE_TYPE = os.getenv("WHISPER_COMPUTE_TYPE", "int8")
BEAM_SIZE = int(os.getenv("WHISPER_BEAM_SIZE", "5"))

app = Flask(__name__)
_model = None


def get_model():
    global _model
    if _model is None:
        _model = WhisperModel(MODEL_SIZE, device=DEVICE, compute_type=COMPUTE_TYPE)
    return _model


def guess_suffix(mime_type: str) -> str:
    mapping = {
        "audio/webm": ".webm",
        "audio/mp4": ".m4a",
        "audio/mpeg": ".mp3",
        "audio/wav": ".wav",
        "audio/x-wav": ".wav",
        "audio/ogg": ".ogg",
    }
    return mapping.get((mime_type or "").split(";")[0].strip().lower(), ".webm")


@app.get("/health")
def health():
    return jsonify(
        {
            "ok": True,
            "model": MODEL_SIZE,
            "device": DEVICE,
            "computeType": COMPUTE_TYPE,
        }
    )


@app.post("/transcribe")
def transcribe():
    payload = request.get_json(silent=True) or {}
    audio_base64 = (payload.get("audioBase64") or "").strip()
    mime_type = (payload.get("mimeType") or "audio/webm").strip()
    language = (payload.get("language") or "zh").strip() or None

    if not audio_base64:
        return jsonify({"error": {"message": "Missing audioBase64"}}), 400

    try:
        audio_bytes = base64.b64decode(audio_base64)
    except Exception:
        return jsonify({"error": {"message": "Invalid base64 audio payload"}}), 400

    if not audio_bytes:
        return jsonify({"error": {"message": "Audio payload is empty"}}), 400

    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=guess_suffix(mime_type)) as tmp:
            tmp.write(audio_bytes)
            tmp_path = Path(tmp.name)

        model = get_model()
        segments, info = model.transcribe(
            str(tmp_path),
            language=language,
            vad_filter=True,
            beam_size=BEAM_SIZE,
        )
        text = "".join(segment.text for segment in segments).strip()
        return jsonify(
            {
                "text": text,
                "language": getattr(info, "language", language),
                "duration": getattr(info, "duration", None),
                "model": MODEL_SIZE,
            }
        )
    except Exception as exc:
        return jsonify({"error": {"message": str(exc)}}), 500
    finally:
        if tmp_path and tmp_path.exists():
            tmp_path.unlink(missing_ok=True)


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8021"))
    app.run(host="0.0.0.0", port=port)
