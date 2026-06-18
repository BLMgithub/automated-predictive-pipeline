FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY data_extractor/requirements.txt .

RUN pip install uv && uv pip install --system -r requirements.txt

COPY data_extractor/ ./data_extractor/

CMD ["python", "-m", "data_extractor.run_extract"]