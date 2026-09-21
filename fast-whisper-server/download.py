#!/usr/bin/env python3
"""
使用 ModelScope 下载 faster-whisper 模型
支持的模型: tiny, base, small, medium, large, large-v2, large-v3
"""

import os
import sys
from pathlib import Path

try:
    from modelscope import snapshot_download
except ImportError:
    print("请先安装 modelscope: pip install modelscope")
    sys.exit(1)

MODEL_MAP = {
    "tiny": "Systran/faster-whisper-tiny",
    "base": "Systran/faster-whisper-base",
    "small": "Systran/faster-whisper-small",
    "medium": "Systran/faster-whisper-medium",
    "large": "Systran/faster-whisper-large-v2",
    "large-v2": "Systran/faster-whisper-large-v2",
    "large-v3": "Systran/faster-whisper-large-v3",
}

def download_model(model_name: str, cache_dir: str = "./models"):
    """下载指定的模型"""
    if model_name not in MODEL_MAP:
        print(f"不支持的模型: {model_name}")
        print(f"支持的模型: {', '.join(MODEL_MAP.keys())}")
        return False

    model_id = MODEL_MAP[model_name]
    print(f"正在下载 {model_name} ({model_id}) ...")
    
    try:
        model_dir = snapshot_download(model_id, cache_dir=cache_dir)
        print(f"下载完成: {model_dir}")
        return True
    except Exception as e:
        print(f"下载失败: {e}")
        return False

def main():
    import argparse
    parser = argparse.ArgumentParser(description="使用 ModelScope 下载 faster-whisper 模型")
    parser.add_argument("model", nargs="?", default="medium", choices=MODEL_MAP.keys(), help="模型名称")
    parser.add_argument("--cache-dir", default="./models", help="缓存目录")
    
    args = parser.parse_args()
    
    success = download_model(args.model, args.cache_dir)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()