# Qwen3.8-27B · llama.cpp 本地部署 (供 Claude Code 使用)

在 4×RTX3090 的机器上用 GPU1/2/3 跑 **Qwen3.8-27B** GGUF 权重，通过 llama.cpp `llama-server`
的 Anthropic 兼容 API (`/v1/messages`, :9150) 作为 Claude Code 的本地推理网关。
仓库里只有配置与脚本，模型权重、llama.cpp 源码、venv 都在项目根且不提交。

## 硬件与速度

| 项目 | 值 |
|------|-----|
| GPU | 3× RTX 3090 (24GB)，`--split-mode tensor`（GPU0 留给其他进程）；可 `TP=2` 退回两卡 |
| 模型 | `Qwen3.8-27B-UD-Q6_K_XL.gguf`（Unsloth 动态量化，24GB）；`Q8_K_XL`(30GB) 仍在 `models/` 备选 |
| 上下文 | 256K (`--ctx-size 262144`，q8_0 KV 量化)，等于模型训练上限 |
| 解码速度 | 思考/代码题 **TP=3 78 t/s** vs TP=2 63 t/s；散文 60–62 t/s 持平 |
| 投机解码 | `--spec-type draft-mtp --spec-draft-n-max 4`（模型自带 MTP 头，无损、零额外下载） |
| 图片 | 支持，mmproj 视觉塔 Q8_0 (0.6GB)，模型原生多模态（27 层 ViT，768×768 输入） |

速度演进：layer 切分 23 t/s → tensor 并行 42 t/s → +draft-mtp 85–99 t/s（短上下文）
→ 切 Q6_K_XL 后 TP=3 78 t/s。

## 目录结构

```
项目根 /data/Projects/qwen3.8-llm/
├── deploy/                    # 本仓库 (部署配置与脚本)
│   ├── start_llama.sh         # 启动 llama-server (Anthropic API :9150)，TP=2/3 可切
│   ├── dl_models.sh           # 下载 GGUF 权重 + mmproj 视觉塔
│   ├── claude-local.sh        # 用本地网关启动 Claude Code
│   ├── qwen3.8-template-fixed.jinja  # 修复过的 chat template
│   ├── metrics_scrape.py      # 抓 /metrics 落成按天 CSV (cron 每分钟)
│   ├── capture_proxy.py       # 诊断用请求转发记录代理 (:9151 -> :9150)
│   ├── start_vllm019.sh       # 备选后端: vLLM 0.19 + W8A8-INT8 + MTP
│   ├── start_vllm_w8a8.sh     # 备选后端: vLLM + SmoothQuant W8A8
│   ├── anthropic_plugin/      # vLLM 的 Anthropic API 端点插件包骨架
│   ├── bench/
│   │   └── bench_qwen27b.py   # 5 道题的 TTFT / decode t/s 基准
│   ├── api_key.txt.example    # API key 模板 (真实 key 放项目根)
│   └── README.md
├── models/                    # GGUF 模型 + mmproj (不提交)
├── llama.cpp/                 # 源码与 build (不提交)
├── vllm-env/ vllm-env-cu128/  # vLLM 虚拟环境 (不提交)
├── api_key.txt                # 真实密钥 (gitignored)
├── metrics/                   # 每日指标 CSV (不提交)
└── llama_server.log           # 服务器日志 (gitignored)
```

## 快速开始

```bash
# 1. 下载权重与视觉塔 (走 hf-mirror, 已存在则跳过 mmproj)
bash deploy/dl_models.sh

# 2. 项目根放真实 key
cp deploy/api_key.txt.example api_key.txt && $EDITOR api_key.txt

# 3. 启动推理服务器 (监听 0.0.0.0:9150, Anthropic API)
bash deploy/start_llama.sh          # 默认 3 卡
TP=2 bash deploy/start_llama.sh     # 退回 2 卡

# 4. 用本地模型启动 Claude Code
bash deploy/claude-local.sh

# 5. 跑分
python3 deploy/bench/bench_qwen27b.py
```

启动参数摘要（详见 `start_llama.sh`）：

- `--split-mode tensor --tensor-split 1,1,1` — 真张量并行，多卡同时算
- `--ctx-size 262144` — 256K 上下文（模型训练上限，超过会被 cap 回来，白占显存）
- `--cache-type-k/v q8_0` — KV 缓存量化，256K 才塞得进显存
- `--spec-type draft-mtp` — 用模型自带 MTP 头做投机解码
- `--mmproj .../mmproj-Qwen3.8-27B-Q8_0.gguf` — 视觉塔，支持图片输入
- `--reasoning on --reasoning-effort medium` — 默认开思考，可被请求里 `reasoning.effort` 覆盖
- `--parallel 1` — 单槽位换最高单流速度；并发请求排队
- `--api-key-file api_key.txt` — 鉴权，`/metrics` 也要带 key
- `--metrics` — Prometheus 指标端点

## 监控指标

`--metrics` 暴露 `GET /metrics`（累计请求数 / 输入输出 tokens / KV 缓存命中率）。
计数器是**进程内**的，重启即清零，所以 `metrics_scrape.py` 把 `server_pid` 也写进 CSV，
算增量时要按 pid 变化分段，否则得到负差值。

```bash
# cron: 每分钟一次，输出 <项目根>/metrics/metrics-YYYY-MM-DD.csv
* * * * * /usr/bin/python3 /data/Projects/qwen3.8-llm/deploy/metrics_scrape.py \
    >/dev/null 2>>/data/Projects/qwen3.8-llm/metrics/scrape.err
```

## 图片输入

Qwen3.8-27B 原生多模态（27 层 ViT）。模型 GGUF 只含文本权重，视觉塔单独一个 mmproj 文件
（`dl_models.sh` 会一起拉）。Claude Code 直接粘贴图片即可，Anthropic 原生 `image` 块会被
服务器转成 `image_url`，每张图约 270 token。

## vLLM 备选路径

llama.cpp 之外还留了两条 vLLM 路：

| 脚本 | 环境 | 权重 | 说明 |
|------|------|------|------|
| `start_vllm019.sh` | `vllm-env-cu128` (vLLM 0.19 + torch 2.10 cu128) | `models/Qwen3.8-27B-W8A8-INT8` | 适配 550.142 驱动；`PORT=9152 TP=2 bash deploy/start_vllm019.sh` |
| `start_vllm_w8a8.sh` | `vllm-env` | `Freaksterz/Qwen3.8-27B-SmoothQuant-W8A8-INT8` | 需 `VLLM_PLUGINS=anthropic`，见 `anthropic_plugin/` |

两者都带 `--speculative-config '{"method":"mtp","num_speculative_tokens":3}'` 和 fp8 KV。
`anthropic_plugin/` 只是骨架：vLLM 0.27.1 的 anthropic 路由存在但未内置注册，
靠 `vllm.endpoint_plugins` 入口点挂上去。

## 已知注意事项

- **长上下文 prefill 变慢**：提示越长首 token 越慢（141K tokens 时 ~1000 t/s，短提示 2300 t/s）；
  接近满上下文解码也下降（实测 229K 时 ~27 t/s）。
- **并发是排队不是并行**：`--parallel 1` 下第二个请求进队列等待，不打断第一个。
  单用户 Claude Code 无影响（客户端本身串行）。要 2 并发就 `--parallel 2` 并把每槽上下文减半。
- **`HTTP_PROXY` 陷阱**：shell 里设了代理时，Python 的 `urllib`/`requests` 会把 localhost 请求
  也发给代理（可能 502）。`metrics_scrape.py` 用 `http.client` 直连，bench 脚本关掉 `trust_env`。
- **`setsid --fork` 的 pid 坑**：`$!` 拿到的是 setsid 自己的 pid，`start_llama.sh` 里会重新
  用 cmdline / `pgrep` 定位真实服务进程再写 `llama_server.pid`。
- **NCCL**：`llama-server` 二进制需链接 `libnccl`（pip 的 `nvidia-nccl-cu12`），
  靠脚本里的 `LD_LIBRARY_PATH` 指到站点包目录，换机器要改这行。
- **良性警告**：`llama_params_fit is not implemented for SPLIT_MODE_TENSOR`、
  `backend sampling not supported with SPLIT_MODE_TENSOR; using CPU` 都属正常。

## 故障排查

| 现象 | 原因/处理 |
|------|-----------|
| 启动即退出 | 看 `llama_server.log`（每次启动会被覆盖）；常见为显存不足或模型路径错 |
| 401 / 无响应 | 请求没带 key；`api_key.txt` 要在**项目根**而不是 `deploy/` |
| `image input is not supported` | 未加载 mmproj，检查 `--mmproj` 路径 |
| 500 错误 | 多半是 chat template 报错，检查请求格式与 `qwen3.8-template-fixed.jinja` |
| `/metrics` 返回非 200 | 服务未就绪或刚重启，`metrics_scrape.py` 会打 ERROR 到 `scrape.err` |
| 服务被连带杀掉 | 确认用了 `setsid --fork`，否则父 shell 会话回收时会一起没 |

## 常见操作

```bash
# 重启服务器
kill "$(cat llama_server.pid)" && bash deploy/start_llama.sh

# 健康检查
curl http://127.0.0.1:9150/health

# 带 key 拉指标
curl -H "x-api-key: $(cat api_key.txt)" http://127.0.0.1:9150/metrics

# 抓 Claude Code 实际发出的请求（:9151 -> :9150）
python3 deploy/capture_proxy.py
```
