#!/bin/bash
# Qwen3.8-27B UD-Q8_K_XL — 2×RTX3090 张量并行 + 投机解码(draft-mtp), Anthropic API(:9150), 供 Claude Code 使用
# 速度: layer切分23 t/s → tensor并行42 t/s → +draft-mtp 85-99 t/s
# 上下文: 256K(q8 KV, 每卡约21.7GB/余2.5GB)
# 图片: --mmproj 加载视觉塔(Q8_0, 0.63GB), 模型原生多模态(27层ViT, 768x768输入)
#
# 项目根 = deploy/ 的上一级目录 (即 /data/Projects/qwen3.8-llm)
# 用法: bash deploy/start_llama.sh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="$PROJECT_ROOT/models"
BIN="$PROJECT_ROOT/llama.cpp/build/bin/llama-server"
export CUDA_VISIBLE_DEVICES=1,2
CHAT_TMPL="$(cat "$PROJECT_ROOT/deploy/qwen3.8-template-fixed.jinja")"

"$BIN" \
  --model "$MODEL_DIR/Qwen3.8-27B-UD-Q8_K_XL.gguf" \
  --mmproj "$MODEL_DIR/mmproj-Qwen3.8-27B-Q8_0.gguf" \
  --alias Qwen3.8-27B \
  --host 0.0.0.0 --port 9150 \
  --n-gpu-layers 999 \
  --split-mode tensor \
  --tensor-split 1,1 \
  --ctx-size 262144 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --parallel 1 \
  --temp 0.7 \
  --api-key-file "$PROJECT_ROOT/api_key.txt" \
  --chat-template "$CHAT_TMPL" \
  --chat-template-kwargs '{"enable_thinking":false}' \
  --spec-type draft-mtp \
  > "$PROJECT_ROOT/llama_server.log" 2>&1 &
echo $! > "$PROJECT_ROOT/llama_server.pid"
echo "llama-server started, PID $(cat "$PROJECT_ROOT/llama_server.pid"), log: llama_server.log"
