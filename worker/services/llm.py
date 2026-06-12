"""
LLM client for local native model servers.

Defaults to Ollama's generate API for compatibility, but supports
OpenAI-compatible servers such as llama.cpp via LLM_API_BASE.
"""
import os
import logging

import httpx

logger = logging.getLogger("cognitive-worker.llm")

LLM_API_BASE = (os.environ.get("LLM_API_BASE") or os.environ.get("OPENAI_BASE_URL", "")).rstrip("/")
LLM_MODEL = os.environ.get("LLM_MODEL", "")
LLM_API_KEY = os.environ.get("LLM_API_KEY") or os.environ.get("OPENAI_API_KEY", "")

OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "deepseek-v4-flash:cloud")
OLLAMA_API_KEY = os.environ.get("OLLAMA_API_KEY", "")


def get_auth_header() -> dict:
    """Returns auth header if API key is configured."""
    if OLLAMA_API_KEY:
        return {"Authorization": f"Bearer {OLLAMA_API_KEY}"}
    return {}


async def openai_chat(prompt: str, model: str | None = None, timeout: int = 120) -> str:
    """Sends a prompt to an OpenAI-compatible chat completions endpoint."""
    if not LLM_API_BASE:
        raise RuntimeError("LLM_API_BASE is required for OpenAI-compatible chat")

    model = model or LLM_MODEL
    if not model:
        raise RuntimeError("LLM_MODEL is required for OpenAI-compatible chat")

    headers = {"Content-Type": "application/json"}
    if LLM_API_KEY:
        headers["Authorization"] = f"Bearer {LLM_API_KEY}"

    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.7,
        "max_tokens": 4096,
    }

    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.post(
            f"{LLM_API_BASE}/chat/completions",
            headers=headers,
            json=payload,
        )
        resp.raise_for_status()
        data = resp.json()

    return data["choices"][0]["message"]["content"]


async def ollama_chat(prompt: str, model: str | None = None, timeout: int = 120) -> str:
    """
    Sends a prompt to the configured local LLM and returns the response.
    Uses LLM_API_BASE when set, otherwise falls back to native Ollama.
    """
    if LLM_API_BASE:
        return await openai_chat(prompt, model=model, timeout=timeout)

    model = model or OLLAMA_MODEL
    url = f"{OLLAMA_BASE_URL}/api/generate"

    headers = {
        "Content-Type": "application/json",
        **get_auth_header(),
    }

    payload = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": 0.7,
            "num_predict": 4096,  # DeepSeek generates long reasoning; needs space
        },
    }

    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.post(url, headers=headers, json=payload)
        resp.raise_for_status()
        data = resp.json()

    # DeepSeek v4 flash: reasoning can consume tokens, leaving response empty
    # Return reasoning if content is empty
    response = data.get("response", "")
    if not response and "reasoning" in data:
        response = data["reasoning"]
    
    return response
