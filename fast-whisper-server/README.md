# fast-whisper-server API 文档

基于 `faster-whisper-server` (OpenAI 兼容的 FastAPI 服务)

## 启动服务

```bash
# 使用配置文件启动（推荐生产环境）
./run.sh start

# 或直接启动
faster-whisper-server --config ./config.yaml --host 0.0.0.0 --port 8000 --workers 4
```

服务默认运行在 `http://localhost:8000`

---

## 接口列表

### 1. 健康检查

**GET** `/health`

```bash
curl "http://localhost:8000/health"
```

**响应:**
```json
{"status": "ok"}
```

---

### 2. 语音转写 (Transcriptions)

将音频转为文本（保持原语言）

**POST** `/v1/audio/transcriptions`

**参数:**

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `file` | file | ✓ | - | 音频文件 (支持 wav, mp3, m4a 等) |
| `model_name` | string | - | `whisper-1` | 模型名称 (对应 config.yaml 中的模型) |
| `language` | string | - | 自动检测 | 语言代码 (如 `zh`, `en`, `ja`) |
| `prompt` | string | - | - | 初始提示词，辅助识别专业术语 |
| `response_format` | string | - | `json` | `json` 或 `verbose_json` |
| `temperature` | float | - | 0.0 | 采样温度 (0-1) |

**示例 - 简单转写:**
```bash
curl -X POST "http://localhost:8000/v1/audio/transcriptions" \
  -F "file=@./关税.wav" \
  -F "model_name=whisper-1" \
  -F "response_format=json"
```

**响应 (json):**
```json
{"text": "识别出的文本内容"}
```

**示例 - 详细输出 (含时间戳、置信度等):**
```bash
curl -X POST "http://localhost:8000/v1/audio/transcriptions" \
  -F "file=@./关税.wav" \
  -F "model_name=whisper-1" \
  -F "language=zh" \
  -F "response_format=verbose_json" \
  -F "temperature=0.0"
```

**响应 (verbose_json):**
```json
{
  "task": "transcribe",
  "language": "zh",
  "duration": 10.5,
  "text": "识别出的文本内容",
  "segments": [
    {
      "id": 0,
      "start": 0.0,
      "end": 5.2,
      "text": "第一段文本",
      "tokens": [123, 456],
      "temperature": 0.0,
      "avg_logprob": -0.3,
      "compression_ratio": 1.2,
      "no_speech_prob": 0.01
    }
  ]
}
```

---

### 3. 语音翻译 (Translations)

将非英语音频翻译为英语文本

**POST** `/v1/audio/translations`

**参数:**

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `file` | file | ✓ | - | 音频文件 |
| `model_name` | string | - | `whisper-1` | 模型名称 |
| `prompt` | string | - | - | 初始提示词 |
| `response_format` | string | - | `json` | `json` 或 `verbose_json` |
| `temperature` | float | - | 0.0 | 采样温度 |

**示例:**
```bash
curl -X POST "http://localhost:8000/v1/audio/translations" \
  -F "file=@./关税.wav" \
  -F "model_name=whisper-1" \
  -F "response_format=json"
```

**响应 (json):**
```json
{"text": "Translated English text"}
```

**示例 - 详细输出:**
```bash
curl -X POST "http://localhost:8000/v1/audio/translations" \
  -F "file=@./关税.wav" \
  -F "model_name=whisper-1" \
  -F "response_format=verbose_json"
```

---

## 配置说明

当前 `config.yaml` 配置的模型：
```yaml
models:
  - name: whisper-1
    path: ./models/models/Systran--faster-whisper-medium/snapshots/master
    model_options:
      device: cuda
      compute_type: int8
    batch_size: 1
```

调用时使用 `model_name: "whisper-1"` 对应此配置。

---

## Python 客户端示例

```python
import requests

# 转写
with open("audio.wav", "rb") as f:
    resp = requests.post(
        "http://localhost:8000/v1/audio/transcriptions",
        files={"file": f},
        data={"model_name": "whisper-1", "language": "zh", "response_format": "verbose_json"}
    )
    print(resp.json())

# 翻译
with open("audio.wav", "rb") as f:
    resp = requests.post(
        "http://localhost:8000/v1/audio/translations",
        files={"file": f},
        data={"model_name": "whisper-1", "response_format": "json"}
    )
    print(resp.json())
```