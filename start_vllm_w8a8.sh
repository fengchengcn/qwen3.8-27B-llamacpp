#!/bin/bash
# vLLM + Qwen3.8-27B W8A8-INT8 (SmoothQuant, Freaksterz) + MTP K=3 — 3090 极限速度实验
# 用法: PORT=9152 TP=2 bash deploy/start_vllm_w8a8.sh
# 参考: https://huggingface.co/Freaksterz/Qwen3.8-27B-SmoothQuant-W8A8-INT8
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VLLM_ENV="$PROJECT_ROOT/vllm-env"
export HF_HOME=/data/cache/zhangqt/huggingface
export TRANSFORMERS_CACHE=/data/cache/zhangqt/huggingface/transformers
export HUGGINGFACE_HUB_CACHE=/data/cache/zhangqt/huggingface/hub
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-1,2}"
export VLLM_PLUGINS=anthropic

PORT="${PORT:-9150}"
TP="${TP:-2}"
KEY="$(cat "$PROJECT_ROOT/api_key.txt")"

"$VLLM_ENV/bin/vllm" serve "Freaksterz/Qwen3.8-27B-SmoothQuant-W8A8-INT8" \
  --host 0.0.0.0 --port "$PORT" \
  --served-model-name Qwen3.8-27B \
  --tensor-parallel-size "$TP" \
  --max-model-len 262144 \
  --kv-cache-dtype fp8_e4m3 \
  --quantization compressed-tensors \
  --enable-prefix-caching \
  --enable-chunked-prefill \
  --reasoning-parser qwen3 \
  --tool-call-parser qwen3_coder \
  --enable-auto-tool-choice \
  --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
  --api-key "$KEY" \
  --gpu-memory-utilization 0.92 \
  > "$PROJECT_ROOT/vllm_server.log" 2>&1 &
echo $! > "$PROJECT_ROOT/vllm_server.pid"
echo "vllm started, PID $(cat "$PROJECT_ROOT/vllm_server.pid"), log: vllm_server.log, port $PORT, TP=$TP"
