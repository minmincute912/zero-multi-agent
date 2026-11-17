FROM python:3.13-slim
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY server.py .
RUN useradd -u 10001 -m app
USER app
ENV PORT=8000
EXPOSE 8000
CMD ["python", "server.py"]
