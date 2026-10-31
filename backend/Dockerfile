FROM python:3.12-slim

# ffmpeg : décodage audio/vidéo pour librosa et OpenCV
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv
COPY requirements.txt requirements-subtitles.txt ./
RUN pip install -r requirements.txt

# Sous-titres IA (≈ +1 Go d'image, torch CPU). Désactiver : --build-arg WITH_SUBTITLES=false
ARG WITH_SUBTITLES=true
RUN if [ "$WITH_SUBTITLES" = "true" ]; then \
      pip install torch --index-url https://download.pytorch.org/whl/cpu \
      && pip install -r requirements-subtitles.txt; \
    fi

COPY app ./app

RUN useradd --create-home aniplay \
    && mkdir -p /srv/data /srv/cache /home/aniplay/.cache/huggingface \
    && chown -R aniplay /srv /home/aniplay
USER aniplay

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8000/health')"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
