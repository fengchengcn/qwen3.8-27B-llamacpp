#!/usr/bin/env python3
"""Benchmark decode speed of Qwen3.8-27B (llama.cpp Anthropic/OpenAI-compatible API).

用法:
  bash deploy/start_llama.sh                # 先起服务
  python3 deploy/bench/bench_qwen27b.py     # 再跑分

可用环境变量覆盖:
  API_KEY   默认读项目根的 api_key.txt (该文件已被 .gitignore 排除, 不要提交)
  PORT      默认 9150
  MODEL     默认 Qwen3.8-27B
  MAX_TOKENS 默认 512
"""
import json
import os
import time

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
DEPLOY = os.path.dirname(HERE)
ROOT = os.path.dirname(DEPLOY)

PORT = int(os.environ.get("PORT", 9150))
MODEL = os.environ.get("MODEL", "Qwen3.8-27B")
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", 512))
URL = "http://127.0.0.1:%d/v1/chat/completions" % PORT


def api_key():
    key = os.environ.get("API_KEY")
    if key:
        return key.strip()
    for path in (os.path.join(ROOT, "api_key.txt"), os.path.join(DEPLOY, "api_key.txt")):
        if os.path.exists(path):
            with open(path) as f:
                return f.read().strip()
    raise SystemExit("找不到 API key: 请放 api_key.txt 到项目根, 或设 API_KEY 环境变量")


def run(prompt, max_tokens=MAX_TOKENS):
    body = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "stream": True,
        "stream_options": {"include_usage": True},
        "max_tokens": max_tokens,
        "temperature": 0.0,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    t0 = time.perf_counter()
    ttft = None
    n_tok = 0
    # localhost 必须绕过代理, 否则环境里设了 HTTP_PROXY 时 urllib/requests 会把请求发给代理并 502
    session = requests.Session()
    session.trust_env = False
    headers = {"Authorization": "Bearer %s" % api_key()}
    with session.post(URL, headers=headers, json=body, stream=True, timeout=300) as r:
        r.raise_for_status()
        for line in r.iter_lines():
            if not line:
                continue
            line = line.decode()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            chunk = json.loads(data)
            if ttft is None and chunk.get("choices") and chunk["choices"][0].get("delta", {}).get("content"):
                ttft = time.perf_counter() - t0
            usage = chunk.get("usage")
            if usage and usage.get("completion_tokens"):
                n_tok = usage["completion_tokens"]
    t1 = time.perf_counter()
    decode_s = (t1 - t0 - ttft) if ttft else (t1 - t0)
    tps = n_tok / decode_s if decode_s > 0 else 0
    return ttft, t1 - t0, n_tok, tps


QUESTIONS = [
    ("短问答", "用一句话解释什么是 TCP 三次握手。"),
    ("中篇写作", "用中文写一段 300 字左右的短文，主题是秋天的城市。"),
    ("代码生成", "用 Python 写一个快速排序函数，并附上简短的复杂度说明。"),
    ("推理题", "一个房间里有 3 盏灯和屋外 3 个开关，每个开关控制一盏灯。"
     "你只能进房间一次，如何确定每个开关对应哪盏灯？"),
    ("长输出", "请详细列出 10 个提高远程团队沟通效率的方法，每个方法给出 2-3 句具体做法。"),
]


def main():
    print("endpoint: %s  model: %s" % (URL, MODEL))
    print("%-8s %9s %11s %11s %14s" % ("问题", "TTFT(s)", "总耗时(s)", "输出tokens", "decode tok/s"))
    print("-" * 58)
    # warmup: 同时把 MTP draft cache 预热起来, 否则第一题偏慢
    run("你好", max_tokens=32)
    for name, q in QUESTIONS:
        ttft, total, n_tok, tps = run(q)
        print("%-8s %9.2f %11.2f %11d %14.2f" % (name, ttft, total, n_tok, tps))


if __name__ == "__main__":
    main()
