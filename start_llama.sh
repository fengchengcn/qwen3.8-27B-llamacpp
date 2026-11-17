#!/bin/bash
# Qwen3.8-27B UD-Q6_K_XL — 2/3×RTX3090 张量并行 + NCCL + 投机解码(draft-mtp), Anthropic API(:9150), 供 Claude Code 使用
# 速度: NCCL 重编译后 TP=3 胜出 (思考/代码题 78 vs TP=2 63 t/s; 散文 60-62 持平), 4卡全用上(除GPU0)
# 权重: 现用 Q6_K_XL (24GB); Q8_K_XL (31GB) 仍在 models/, 换权重改 --model 即可
# 并发: --parallel 1 单槽位 = 最高单流速度; 若需2并发改 --parallel 2 + --ctx-size 262144(每槽128K)
# 上下文: --ctx-size 262144 = 256K 单槽 (q8 KV) = 模型训练上限(max_position_embeddings=262144); 超训练上下文会被 llama.cpp 强制 cap 回 262144, 无效且白占显存
# NCCL: 二进制需链接 libnccl (pip 安装的 nvidia-nccl-cu12), 见下方 LD_LIBRARY_PATH
# 图片: --mmproj 加载视觉塔(Q8_0, 0.63GB), 模型原生多模态(27层ViT, 768x768输入)
# 思考: --reasoning on + --reasoning-effort medium 为默认思考强度(可被请求内 reasoning.effort 覆盖)
#
# 监控: --metrics 开启 Prometheus 指标端点 (GET /metrics, 需 API key), 累计请求数/输入输出 tokens/KV 缓存命中率
#       注意: 计数器是进程内的, 重启后清零; 日志 llama_server.log 亦会被本次启动覆盖
# 项目根 = deploy/ 的上一级目录 (即 /data/Projects/qwen3.8-llm)
# 用法: bash deploy/start_llama.sh
# 切换卡数: TP=2 bash deploy/start_llama.sh  (默认 3 卡)
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="$PROJECT_ROOT/models"
BIN="$PROJECT_ROOT/llama.cpp/build/bin/llama-server"
# NCCL 运行时库 (pip 安装的 nvidia-nccl-cu12)
export LD_LIBRARY_PATH="/data/minconda3/lib/python3.12/site-packages/nvidia/nccl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ====== GPU 数量切换 (默认 3 卡，设 TP=2 启用 2 卡模式) ======
TP="${TP:-3}"
if [[ "$TP" == "2" ]]; then
  export CUDA_VISIBLE_DEVICES=1,2
  TENSOR_SPLIT="1,1"
  echo "🔧 启用 2 卡模式 (GPU 1,2)，tensor-split=1,1"
else
  export CUDA_VISIBLE_DEVICES=1,2,3
  TENSOR_SPLIT="1,1,1"
  echo "🔧 启用 3 卡模式 (GPU 1,2,3)，tensor-split=1,1,1"
fi

CHAT_TMPL="$(cat "$PROJECT_ROOT/deploy/qwen3.8-template-fixed.jinja")"

# setsid --fork: 脱离本 shell 的会话与进程组, 否则父 shell 会话回收时服务会被一起杀掉
setsid --fork "$BIN" \
  --model "$MODEL_DIR/Qwen3.8-27B-UD-Q6_K_XL.gguf" \
  --mmproj "$MODEL_DIR/mmproj-Qwen3.8-27B-Q8_0.gguf" \
  --alias Qwen3.8-27B \
  --host 0.0.0.0 --port 9150 \
  --n-gpu-layers 999 \
  --split-mode tensor \
  --tensor-split "$TENSOR_SPLIT" \
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
  --metrics \
  > "$PROJECT_ROOT/llama_server.log" 2>&1 &
PID=$!
sleep 2
# setsid --fork 总是 fork 后再退出, 所以 $! 是 setsid 自己的 pid, 必须重新定位真实服务进程
if ! tr '\0' ' ' 2>/dev/null < "/proc/$PID/cmdline" | grep -q "llama-server"; then
  PID="$(pgrep -f "llama-server --model $MODEL_DIR/Qwen3.8-27B-UD-Q6_K_XL.gguf" | head -1)"
fi
echo "$PID" > "$PROJECT_ROOT/llama_server.pid"
echo "llama-server started, PID $PID, log: llama_server.log"
