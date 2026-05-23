# Rivaro for Developers

Runtime governance for AI agents. Detect risks, enforce policies, and audit every decision -- transparently, with zero code changes to your agent.

## Quick Install

```bash
curl -fsSL https://get.rivaro.ai/dev | bash
```

This starts Rivaro locally with Docker. You'll have:

- **Dashboard** at [http://localhost:3000](http://localhost:3000)
- **Proxy** at [http://localhost:8080](http://localhost:8080)

The installer runs a test detection automatically -- you'll see an SSN and email address caught and redacted in real time.

## Connect Your Agent

Point your AI SDK at the Rivaro proxy instead of the provider directly. Two changes: `base_url` and an `X-Detection-Key` header.

### Python (OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8080/v1",
    api_key="sk-your-openai-key",
    default_headers={"X-Detection-Key": "YOUR_DETECTION_KEY"}
)

response = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Hello, world!"}]
)
```

### Node.js

```javascript
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: 'http://localhost:8080/v1',
  apiKey: 'sk-your-openai-key',
  defaultHeaders: { 'X-Detection-Key': 'YOUR_DETECTION_KEY' }
});
```

Your detection key is displayed on the dashboard welcome page after first startup.

## What Gets Detected

Every request and response is scanned for:

| Category | Examples |
|----------|----------|
| **Credentials** | API keys, SSH keys, tokens, passwords |
| **PII** | Emails, phone numbers, SSNs, addresses |
| **Prompt injection** | Jailbreak attempts, instruction override |
| **Tool abuse** | Unauthorized file access, shell commands, network requests |
| **Data exfiltration** | Sensitive data leaving to external endpoints |
| **Financial data** | Bank accounts, routing numbers, credit cards |

## Managing Your Installation

```bash
cd ~/.rivaro/developer

docker compose logs -f         # stream logs
docker compose down            # stop services
docker compose down -v         # reset all data
docker compose up -d           # restart
```

## Pre-configure a Provider Key

Pass your API key when installing to route real LLM requests:

```bash
OPENAI_API_KEY=sk-your-key curl -fsSL https://get.rivaro.ai/dev | bash
```

## Framework Guides

Rivaro works with any OpenAI-compatible agent framework:

- [LangChain](https://docs.rivaro.ai/agent-frameworks#langchain-python)
- [CrewAI](https://docs.rivaro.ai/agent-frameworks#crewai)
- [Vercel AI SDK](https://docs.rivaro.ai/agent-frameworks#vercel-ai-sdk)
- [AutoGen](https://docs.rivaro.ai/agent-frameworks#autogen)
- [Anthropic](https://docs.rivaro.ai/agent-frameworks#using-anthropic-through-rivaro)

## Documentation

Full docs at [docs.rivaro.ai](https://docs.rivaro.ai):

- [Developer Quickstart](https://docs.rivaro.ai/developer-quickstart)
- [Agent Frameworks](https://docs.rivaro.ai/agent-frameworks)
- [Enforcement & Policies](https://docs.rivaro.ai/enforcement)
- [MCP Governance](https://docs.rivaro.ai/mcp)
- [How Rivaro Works](https://docs.rivaro.ai/how-it-works)

## System Requirements

- Docker and Docker Compose
- 4 GB RAM available for containers
- macOS, Linux, or WSL2

## About Rivaro

Rivaro is the governance control plane for AI agents. It sits between your agents and the services they call, enforcing policy at runtime without changing your agent code.

- **Proxy** intercepts LLM calls (OpenAI, Anthropic, Bedrock, Vertex, Azure) for real-time detection
- **Sidecar** intercepts agent tool calls for pre-execution policy enforcement
- **Dashboard** gives you visibility into your entire agent estate

Learn more at [rivaro.ai](https://rivaro.ai)
