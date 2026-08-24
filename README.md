# Qwen3.8-27B · llama.cpp 本地部署 (供 Claude Code 使用)

用 2×RTX3090 在本地跑 **Qwen3.8-27B UD-Q8_K_XL**，通过 llama.cpp `llama-server` 的
Anthropic 兼容 API (`/v1/messages`) 作为 Claude Code 的后端推理网关。

## 硬件与速度

| 项目 | 值 |
|------|-----|
| GPU | 2× RTX 3090 (24GB) 张量并行 (`--split-mode tensor --tensor-split 1,1`) |
| 模型 | `Qwen3.8-27B-UD-Q8_K_XL.gguf` (Unsloth 动态量化, Q8_K_XL, ~31.5GB) |
| 上下文 | 256K (q8_0 KV 缓存量化) |
| 解码速度 | 短上下文 **85–99 t/s** (draft-mtp 投机解码) |
| 图片 | 支持 (mmproj 视觉塔, Q8_0, 0.63GB) |

速度演进：layer 切分 23 t/s → tensor 并行 42 t/s → +draft-mtp 85–99 t/s。

## 目录结构

```
项目根 /data/Projects/qwen3.8-llm/
├── deploy/                    # 本仓库 (部署配置)
│   ├── start_llama.sh         # 启动 llama-server (Anthropic API :9150)
│   ├── claude-local.sh        # 启动 Claude Code 指向本地网关
│   ├── qwen3.8-template-fixed.jinja   # 修复过的 chat template
│   ├── capture_proxy.py       # 诊断用请求转发记录代理 (:9151 -> :9150)
│   ├── api_key.txt.example    # API key 模板 (真实 key 放项目根)
│   └── README.md
├── models/                    # GGUF 模型 + mmproj (不提交)
├── llama.cpp/                 # 源码与 build (不提交)
├── api_key.txt                # 真实密钥 (gitignored)
└── llama_server.log           # 服务器日志 (gitignored)
```

## 快速开始

```bash
# 1. 启动推理服务器 (监听 0.0.0.0:9150, Anthropic API)
bash deploy/start_llama.sh

# 2. 用本地模型启动 Claude Code
bash deploy/claude-local.sh
```

启动参数摘要（详见 `start_llama.sh`）：

- `--split-mode tensor --tensor-split 1,1` — 真张量并行，两块卡同时算
- `--ctx-size 262144` — 256K 上下文（模型训练上限）
- `--cache-type-k/v q8_0` — KV 缓存量化，256K 才能塞进 2×24GB
- `--spec-type draft-mtp` — 用模型自带 MTP 头做投机解码（无损，零额外下载）
- `--mmproj .../mmproj-Qwen3.8-27B-Q8_0.gguf` — 视觉塔，支持图片输入
- `--parallel 1` — 单槽位；并发请求按 FIFO 排队

## 图片输入

Qwen3.8-27B 原生多模态（27 层 ViT）。模型 GGUF 只含文本权重，视觉塔在 mmproj 文件里：

```bash
# 下载（若本机无此文件）
curl -L -o models/mmproj-Qwen3.8-27B-Q8_0.gguf \
  https://huggingface.co/ggml-org/Qwen3.8-27B-GGUF/resolve/main/mmproj-Qwen3.8-27B-Q8_0.gguf
```

Claude Code 直接粘贴图片即可（Anthropic 原生 `image` 块会被服务器转换为 `image_url`）。
每张图约消耗 270 个 token。

## 已知注意事项

- **长上下文 prefill 变慢**：提示词越长首 token 越慢（141K tokens 时 ~1000 t/s，
  短提示 2300 t/s）。接近满上下文时解码也会明显下降（实测 229K 时 ~27 t/s）。
- **并发是排队不是并行**：`--parallel 1` 下第二个请求进任务队列等待，不会中断第一个。
  对单用户 Claude Code 无影响（客户端本身串行）。
- **`HTTP_PROXY` 陷阱**：如果 shell 里设了 `HTTP_PROXY`，Python 的 `urllib` 会把
  localhost 请求也走代理（可能 502）。测试 API 时请绕过代理或用 curl。
- **良性警告**：`llama_params_fit is not implemented for SPLIT_MODE_TENSOR`、
  `backend sampling not supported with SPLIT_MODE_TENSOR; using CPU` 均属正常。
- **GPU 选择**：`CUDA_VISIBLE_DEVICES=1,2` 用 GPU1/2，GPU0 留给了其他进程。

## 故障排查

| 现象 | 原因/处理 |
|------|-----------|
| 启动即退出 | 看 `llama_server.log`；常见为显存不足或模型路径错 |
| `image input is not supported` | 未加载 mmproj，检查 `--mmproj` 路径 |
| 500 错误 | 多半是 template 报错，检查请求格式 |
| 想多客户端并发 | `--parallel N` 但每槽上下文会缩水；单用户无需 |

## 常见操作

```bash
# 重启服务器
kill "$(cat llama_server.pid)" && bash deploy/start_llama.sh

# 健康检查
curl http://127.0.0.1:9150/health

# 测试图片输入 (Anthropic 格式, base64)
# 见会话记录或 capture_proxy.py
```
