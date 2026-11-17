# Playwright image already contains Chromium and its system libraries; the pip package version must match the tag.
FROM mcr.microsoft.com/playwright/python:v1.65.2-noble
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-venv xvfb x11vnc novnc websockify \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
# A venv avoids pip fighting the Debian-managed system packages (typing_extensions has no RECORD file).
RUN python3 -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY server.py start.sh ./
RUN chmod +x start.sh
EXPOSE 8001 6080
CMD ["/app/start.sh"]
