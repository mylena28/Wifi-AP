FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir flask

COPY gallery.py .

CMD ["python3", "gallery.py"]
