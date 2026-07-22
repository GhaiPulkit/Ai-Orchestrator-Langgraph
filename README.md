# LangGraph AI Orchestrator

Natural language → GraphQL API calls → natural language — built on **LangGraph /
LangChain**, with **Langfuse** for observability.

This is a port of the original hand-rolled orchestrator to the LangChain stack.
It points at any GraphQL SDL schema, exposes every root **Query** (and optionally
**Mutation**) field to Claude on AWS Bedrock as a tool, and runs a LangGraph
state machine that loops until it has a plain-language answer. Every run is traced
to Langfuse.

```
              ┌───────┐   tool_calls?   ┌───────┐
 user ─▶ HumanMessage │ agent │ ──────────────▶ │ tools │ ─▶ GraphQL op
              └───────┘ ◀────────────── └───────┘
                  │ no tool_calls          (results as ToolMessages)
                  ▼
                answer
```

## How it works

| File | Responsibility |
|------|----------------|
| `langgraph_orchestrator/schema_tools.py` | Parse SDL → one tool spec per Query/Mutation field; auto-expand return selection sets; rebuild the GraphQL operation + variables from a tool call. *(shared logic with the original project)* |
| `langgraph_orchestrator/graphql_client.py` | Execute operations over HTTP with a configurable auth header. |
| `langgraph_orchestrator/agent.py` | The LangGraph agent: `ChatBedrockConverse` with tools bound, an `agent` node and a `tools` node, looping until the model answers. Wires the Langfuse callback. |
| `langgraph_orchestrator/server.py` | FastAPI HTTP server (`/prompt`, `/tools`, `/health`, Swagger `/docs`). |
| `langgraph_orchestrator/__main__.py` | CLI — one-shot, interactive REPL, and `--list-tools`. |
| `langgraph_orchestrator/config.py` | Environment / `.env` configuration. |

The GraphQL tools are generated dynamically from the schema and bound to the
model with `bind_tools`. The `tools` node reads `message.tool_calls`, reconstructs
each GraphQL operation, executes it, and feeds results back as `ToolMessage`s —
the same contract the original loop used, expressed as a graph. `recursion_limit`
bounds the agent↔tools cycles so a confused model can't loop forever.

## How this differs from the original

| | Original (`ai-orchestrator`) | This project |
|--|--|--|
| Loop | Hand-rolled `while` over the Anthropic Messages API | LangGraph `StateGraph` (`agent` ⇄ `tools`) |
| Model client | `AnthropicBedrock` | `langchain_aws.ChatBedrockConverse` |
| Tools | Anthropic tool specs | same specs → `bind_tools` (OpenAI function format) |
| Observability | none | Langfuse tracing (LangChain callback) |
| Config / server / CLI | — | same env vars, endpoints, and commands |

## Setup

Requires Python 3.10+.

```bash
pip install -r requirements.txt
cp .env.example .env      # then edit .env
```

Key env vars (same as the original, plus Langfuse):

- **AWS credentials** — standard AWS chain; set `AWS_REGION` + keys or `aws configure`.
- **`BEDROCK_MODEL_ID`** — e.g. `us.anthropic.claude-sonnet-5`.
- **`GRAPHQL_ENDPOINT` / `GRAPHQL_SCHEMA_PATH`** — your API and its SDL file.
- **`GRAPHQL_AUTH_HEADER` / `GRAPHQL_AUTH_TOKEN`** — auth sent with each request.
- **`ALLOW_MUTATIONS`** — `false` (default) = read-only, queries only.
- **`TOOL_INCLUDE` / `TOOL_EXCLUDE`** — regexes to narrow the tool set.
- **`LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY` / `LANGFUSE_HOST`** — tracing.

## Usage

```bash
# One-shot
python -m langgraph_orchestrator "how many loan applications are there?"

# Interactive REPL
python -m langgraph_orchestrator

# Inspect the tools generated from your schema (no API calls)
python -m langgraph_orchestrator --list-tools
```

## HTTP server

```bash
python -m langgraph_orchestrator.server     # binds $HOST (0.0.0.0) : $PORT (8000)
```

| Endpoint | Description |
|----------|-------------|
| `POST /prompt` | Body `{"prompt": "..."}` → `{"answer": ..., "tool_calls": [...]}` |
| `GET /tools` | The tools generated from your schema. |
| `GET /health` | `{"status": "ok", "tools": <n>, "framework": "langgraph", "tracing": ...}` |
| `GET /docs` | Interactive Swagger UI. |

## Docker Compose

```bash
cp .env.example .env      # then edit .env
docker compose up --build
```

Then prompt it via the browser (`/docs`), curl, or
`docker compose exec orchestrator python -m langgraph_orchestrator "..."`.

## Observability (Langfuse)

Set `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY` (and `LANGFUSE_HOST` if
self-hosted). Tracing then turns on automatically: the agent attaches Langfuse's
LangChain `CallbackHandler` to every graph run, so each request appears in
Langfuse as a trace with the LLM calls, tool (GraphQL) calls, inputs/outputs,
latency, and token usage. `/health` reports `"tracing": "langfuse"` when active,
`"off"` when keys are absent. With no keys the orchestrator runs exactly the
same, just untraced.
