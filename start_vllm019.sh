#!/bin/bash
# vLLM 0.19.0 + torch 2.10 cu128 + Qwen3.8-27B W8A8-INT8 (SmoothQuant) + MTP K=3
# 适配 550.142 驱动 (cu128). 用法: PORT=9152 TP=2 bash deploy/start_vllm019.sh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VLLM_ENV="$PROJECT_ROOT/vllm-env-cu128"
VLLM="$VLLM_ENV/bin/vllm"
export PATH="$VLLM_ENV/bin:$PATH"
export HF_HOME=/data/cache/zhangqt/huggingface
export TRANSFORMERS_CACHE=/data/cache/zhangqt/huggingface/transformers
export HUGGINGFACE_HUB_CACHE=/data/cache/zhangqt/huggingface/hub
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-1,2}"
PORT="${PORT:-9150}"
TP="${TP:-2}"
KEY="$(cat "$PROJECT_ROOT/api_key.txt")"

"$VLLM" serve "$PROJECT_ROOT/models/Qwen3.8-27B-W8A8-INT8" \
  --host 0.0.0.0 --port "$PORT" \
  --served-model-name Qwen3.8-27B \
  --tensor-parallel-size "$TP" \
  --max-model-len "${MAXLEN:-131072}" \
  --kv-cache-dtype fp8_e4m3 \
  --quantization compressed-tensors \
  --gpu-memory-utilization "${UTIL:-0.95}" \
  --compilation-config '{"cudagraph_capture_sizes":[1,2,4,8,16,24,32,40,48,56,64]}' \
  --enable-prefix-caching \
  --enable-chunked-prefill \
  --reasoning-parser qwen3 \
  --tool-call-parser qwen3_coder \
  --enable-auto-tool-choice \
  --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
  --api-key "$KEY" \
  > "$PROJECT_ROOT/vllm_server.log" 2>&1 &
echo $! > "$PROJECT_ROOT/vllm_server.pid"
echo "vllm019 started, PID $(cat "$PROJECT_ROOT/vllm_server.pid"), log: vllm_server.log, port $PORT, TP=$TP"
