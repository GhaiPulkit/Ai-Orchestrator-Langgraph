FROM python:3.12-slim

# Don't buffer stdout/stderr; don't write .pyc files.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Install deps first so the layer caches across code changes.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# App code.
COPY langgraph_orchestrator/ ./langgraph_orchestrator/
COPY sample.graphql ./
COPY schemas/ ./schemas/

# AWS credentials, GraphQL endpoint, and Langfuse keys are supplied at runtime
# via env / .env (see .env.example). Nothing secret is baked into the image.
ENTRYPOINT ["python", "-m", "langgraph_orchestrator"]
CMD ["--list-tools"]
