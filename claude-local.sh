#!/bin/bash
# 用本地 Qwen3.8-27B (llama-server :8080) 启动 Claude Code
export ANTHROPIC_BASE_URL=http://127.0.0.1:9150
export ANTHROPIC_AUTH_TOKEN=local-dev
export ANTHROPIC_MODEL=Qwen3.8-27B
export ANTHROPIC_DEFAULT_OPUS_MODEL=Qwen3.8-27B
export ANTHROPIC_DEFAULT_SONNET_MODEL=Qwen3.8-27B
export ANTHROPIC_DEFAULT_HAIKU_MODEL=Qwen3.8-27B
exec claude "$@"
