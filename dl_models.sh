#!/bin/bash
# 下载 Qwen3.8-27B 的 GGUF 权重和 mmproj 视觉塔到项目根 models/
# 用法:
#   bash deploy/dl_models.sh                                  # 默认 Q6_K_XL
#   bash deploy/dl_models.sh Qwen3.8-27B-UD-Q8_K_XL.gguf     # 换量化
#   PYTHON=/path/to/python bash deploy/dl_models.sh           # 指定带 huggingface_hub 的解释器
# 走 hf-mirror 时需要直连, 默认把代理变量清掉 (USE_PROXY=1 可保留)
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="$PROJECT_ROOT/models"
QUANT="${1:-Qwen3.8-27B-UD-Q6_K_XL.gguf}"
PYTHON="${PYTHON:-$PROJECT_ROOT/vllm-env-cu128/bin/python}"
HF_REPO="${HF_REPO:-unsloth/Qwen3.8-27B-GGUF}"
MMPROJ_REPO="${MMPROJ_REPO:-ggml-org/Qwen3.8-27B-GGUF}"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_HUB_DISABLE_XET=1
[[ "${USE_PROXY:-0}" == "1" ]] || unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy

mkdir -p "$MODEL_DIR"

"$PYTHON" - "$HF_REPO" "$QUANT" "$MODEL_DIR" <<'PY'
import sys
from huggingface_hub import snapshot_download

repo, quant, model_dir = sys.argv[1:4]
path = snapshot_download(repo, allow_patterns=[quant], local_dir=model_dir)
print("SNAPSHOT_DONE", path)
PY

MMPROJ="$MODEL_DIR/mmproj-Qwen3.8-27B-Q8_0.gguf"
if [[ -f "$MMPROJ" ]]; then
  echo "mmproj 已存在, 跳过: $MMPROJ"
else
  curl -L -o "$MMPROJ" "$HF_ENDPOINT/$MMPROJ_REPO/resolve/main/mmproj-Qwen3.8-27B-Q8_0.gguf"
  echo "MMPROJ_DONE $MMPROJ"
fi
