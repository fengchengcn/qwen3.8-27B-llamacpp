#!/bin/bash
# Qwen3.8-27B UD-Q8_K_XL — 3×RTX3090 张量并行 + NCCL + 投机解码(draft-mtp), Anthropic API(:9150), 供 Claude Code 使用
# 速度: NCCL 重编译后 TP=3 胜出 (思考/代码题 78 vs TP=2 63 t/s; 散文 60-62 持平), 4卡全用上(除GPU0)
# 并发: --parallel 1 单槽位 = 最高单流速度; 若需2并发改 --parallel 2 + --ctx-size 262144(每槽128K)
# 上下文: --ctx-size 262144 = 256K 单槽 (q8 KV) = 模型训练上限(max_position_embeddings=262144); 超训练上下文会被 llama.cpp 强制 cap 回 262144, 无效且白占显存
# NCCL: 二进制需链接 libnccl (pip nvidia-nccl-cu12), 见下方 LD_LIBRARY_PATH
# 图片: --mmproj 加载视觉塔(Q8_0, 0.63GB), 模型原生多模态(27层ViT, 768x768输入)
# 思考: --reasoning on + --reasoning-effort medium 为默认思考强度(可被请求内 reasoning.effort 覆盖)
#
# 项目根 = deploy/ 的上一级目录 (即 /data/Projects/qwen3.8-llm)
# 用法: bash deploy/start_llama.sh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="$PROJECT_ROOT/models"
BIN="$PROJECT_ROOT/llama.cpp/build/bin/llama-server"
# NCCL 运行时库 (pip 安装的 nvidia-nccl-cu12)
export LD_LIBRARY_PATH="/data/minconda3/lib/python3.12/site-packages/nvidia/nccl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CUDA_VISIBLE_DEVICES=1,2,3
CHAT_TMPL="$(cat "$PROJECT_ROOT/deploy/qwen3.8-template-fixed.jinja")"

"$BIN" \
  --model "$MODEL_DIR/Qwen3.8-27B-UD-Q6_K_XL.gguf" \
  --mmproj "$MODEL_DIR/mmproj-Qwen3.8-27B-Q8_0.gguf" \
  --alias Qwen3.8-27B \
  --host 0.0.0.0 --port 9150 \
  --n-gpu-layers 999 \
  --split-mode tensor \
  --tensor-split 1,1,1 \
  --ctx-size 262144 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --parallel 1 \
  --temp 0.7 \
  --api-key-file "$PROJECT_ROOT/api_key.txt" \
  --chat-template "$CHAT_TMPL" \
  --reasoning on \
  --reasoning-effort medium \
  --flash-attn on \
  --spec-type draft-mtp \
  --spec-draft-n-max 4 \
  > "$PROJECT_ROOT/llama_server.log" 2>&1 &
echo $! > "$PROJECT_ROOT/llama_server.pid"
echo "llama-server started, PID $(cat "$PROJECT_ROOT/llama_server.pid"), log: llama_server.log"
