FROM python:3.13-slim
WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN useradd -u 10001 app
COPY app app
ARG APP_VERSION=v1
ENV APP_VERSION=$APP_VERSION DB_PATH=/data/demo.db
USER 10001
CMD ["gunicorn", "-b", "0.0.0.0:8000", "-w", "2", "app.main:app"]
