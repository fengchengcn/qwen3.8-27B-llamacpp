#!/usr/bin/env python3
"""抓取 llama-server 的 /metrics 并追加为 CSV 宽表, 按天分文件。

输出: <项目根>/metrics/metrics-YYYY-MM-DD.csv
  一行 = 一次抓取快照, 列为 timestamp, server_pid + 各指标名

指标是进程内累计计数器, 服务重启后清零 —— server_pid 列用来标记重启边界,
算增量时要按 pid 变化分段重算, 否则会得到负的差值。

cron(每分钟):
  * * * * * /usr/bin/python3 /data/Projects/qwen3.8-llm/deploy/metrics_scrape.py \
      >/dev/null 2>>/data/Projects/qwen3.8-llm/metrics/scrape.err
"""
import csv
import http.client
import os
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "metrics")
HOST, PORT = "127.0.0.1", 9150


def api_key():
    with open(os.path.join(ROOT, "api_key.txt")) as f:
        return f.read().strip()


def server_pid():
    try:
        with open(os.path.join(ROOT, "llama_server.pid")) as f:
            return f.read().strip()
    except OSError:
        return ""


def scrape():
    # 用 http.client 直连: 环境里若有 HTTP_PROXY, urllib 会把 localhost 请求也走代理而 502
    conn = http.client.HTTPConnection(HOST, PORT, timeout=10)
    try:
        conn.request("GET", "/metrics", headers={"x-api-key": api_key()})
        resp = conn.getresponse()
        if resp.status != 200:
            raise RuntimeError("GET /metrics -> HTTP %d" % resp.status)
        text = resp.read().decode("utf-8", "replace")
    finally:
        conn.close()

    metrics = {}
    for line in text.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        name, _, value = line.rpartition(" ")
        metrics[name] = value
    if not metrics:
        raise RuntimeError("/metrics 返回内容中没有指标")
    return metrics


def main():
    values = scrape()
    names = sorted(values)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, "metrics-%s.csv" % datetime.now().strftime("%Y-%m-%d"))

    header = None
    if os.path.exists(path) and os.path.getsize(path) > 0:
        with open(path, newline="") as f:
            header = next(csv.reader(f), None)
    # 指标集若因 llama.cpp 升级而变动, 沿用文件已有的列序, 避免行与表头错位
    if header:
        names = [n for n in header[2:] if n in names]

    row = [datetime.now().isoformat(timespec="seconds"), server_pid()]
    row += [values.get(n, "") for n in names]

    with open(path, "a", newline="") as f:
        w = csv.writer(f)
        if not header:
            w.writerow(["timestamp", "server_pid"] + names)
        w.writerow(row)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # 服务未就绪/重启中属正常, 打点缺失在 CSV 里表现为时间戳断档
        sys.stderr.write("%s ERROR %s: %s\n" % (datetime.now().isoformat(timespec="seconds"), type(e).__name__, e))
        raise SystemExit(1)
