FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8021 \
    WHISPER_MODEL_SIZE=small \
    WHISPER_DEVICE=auto \
    WHISPER_COMPUTE_TYPE=int8 \
    WHISPER_BEAM_SIZE=5

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8021

CMD ["gunicorn", "--bind", "0.0.0.0:8021", "--workers", "1", "--threads", "2", "--timeout", "300", "app:app"]
