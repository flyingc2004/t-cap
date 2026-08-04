# T-CaP / CaP-X 最小复现脚本

这个仓库用于在本机 8 卡 RTX 4090 服务器上复现 CaP-X 的 Robosuite Cube Stack 最小流程。仓库只保存可复现代码和脚本，不保存 Python 环境、缓存、模型权重、运行输出或 API token。

## 仓库结构

```text
t-cap/
  cap-x/                 # CaP-X 官方仓库，作为 git submodule 固定版本
  capx_scripts/          # 本仓库提供的一键安装、检查、API proxy 和评测脚本
  README.md              # 当前说明
```

当前 `cap-x` 固定到：

```text
53e9966d7a8e2fa7494676772bccc35280f5c0ed
```

## 1. 克隆仓库

不要使用 `--recursive`，否则可能递归下载 CaP-X 的全部 third_party 子模块。先只初始化顶层 `cap-x` 子模块：

```bash
git clone https://github.com/flyingc2004/t-cap.git
cd t-cap
git submodule update --init cap-x
```

后续 `setup_capx.sh` 只会初始化 Cube Stack 必需的三个 CaP-X nested submodules：

```text
capx/third_party/robosuite
capx/third_party/sam3
capx/third_party/contact_graspnet_pytorch
```

## 2. 安装环境

脚本默认：

- 不使用 sudo；
- 不使用 Docker；
- 使用 Python 3.10；
- 使用 `uv` 管理环境；
- 默认 GPU 为物理 `7` 号卡；
- 缓存写到 `./cap-x-cache`；
- 运行输出写到 `./capx-runs`；
- 临时文件写到 `/dev/shm/$USER/capx-tmp`。

执行：

```bash
bash capx_scripts/setup_capx.sh
```

如果服务器访问 GitHub/PyPI 需要代理，先在同一个终端设置代理，例如：

```bash
export http_proxy=http://127.0.0.1:17897
export https_proxy=http://127.0.0.1:17897
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
export NO_PROXY=127.0.0.1,localhost
export no_proxy=127.0.0.1,localhost

bash capx_scripts/setup_capx.sh
```

如果安装过程中网络中断，直接重跑安装脚本即可：

```bash
CAPX_GIT_RETRIES=6 bash capx_scripts/setup_capx.sh
```

## 3. 检查环境

```bash
bash capx_scripts/check_capx.sh
```

检查内容包括：

- Python 3.10；
- CUDA / PyTorch 可见；
- `capx`、`mujoco`、`robosuite`、`OpenGL.EGL`、`torch`、`contact_graspnet_pytorch` 可导入；
- 8110、8114、8115、8116 端口占用情况。

如果提示 `ModuleNotFoundError: No module named 'mujoco'` 或其他依赖缺失，修复当前 `.venv`：

```bash
bash capx_scripts/repair_capx_env.sh
bash capx_scripts/check_capx.sh
```

## 4. 准备 token

CaP-X Cube Stack 默认需要两个外部访问权限：

- OpenRouter API key：用于调用 LLM；
- Hugging Face token：用于下载 SAM3 gated checkpoint。

不要在共享服务器上持久登录 token。脚本会隐藏读取 token，并尽量只保存在当前进程或 `/dev/shm`。

SAM3 权限需要先在网页接受：

```text
https://huggingface.co/facebook/sam3
```

## 5. 启动 OpenRouter API proxy

终端 A：

```bash
bash capx_scripts/run_capx_api.sh
```

默认监听：

```text
http://127.0.0.1:8110/chat/completions
```

如需换端口：

```bash
CAPX_PROXY_PORT=8120 bash capx_scripts/run_capx_api.sh
```

## 6. 运行单条 smoke

保持终端 A 的 proxy 不要关闭。终端 B：

```bash
bash capx_scripts/run_capx_cube_stack.sh smoke
```

`smoke` 默认：

- 1 trial；
- 1 worker；
- 不录视频；
- 模型 `google/gemini-3.1-pro-preview`；
- GPU 7。

## 7. 运行 10 条 quick

单条 smoke 没有 API、CUDA、MuJoCo、SAM3、ContactGraspNet 或 PyRoKi 错误后，再跑：

```bash
bash capx_scripts/run_capx_cube_stack.sh quick
```

`quick` 默认：

- 10 trials；
- 5 workers；
- 录制视频。

结果目录：

```text
capx-runs/cube_stack_quick_<UTC时间>/
```

其中：

- `run_config.txt`：本次运行配置；
- `evaluation.log`：完整日志；
- `outputs/`：CaP-X 输出、生成代码和视频。

## 常用参数

```bash
CAPX_GPU=3 \
CAPX_MODEL=google/gemini-3.1-pro-preview \
CAPX_TRIALS=3 \
CAPX_WORKERS=1 \
CAPX_RECORD_VIDEO=False \
bash capx_scripts/run_capx_cube_stack.sh smoke
```

常用环境变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `CAPX_GPU` | `7` | 使用的物理 GPU 编号 |
| `CAPX_MODEL` | `google/gemini-3.1-pro-preview` | OpenRouter 模型 ID |
| `CAPX_PROXY_PORT` | `8110` | 本地 API proxy 端口 |
| `CAPX_TRIALS` | 模式默认值 | trial 数量 |
| `CAPX_WORKERS` | 模式默认值 | 并发 worker 数量 |
| `CAPX_RECORD_VIDEO` | 模式默认值 | 是否录制视频 |
| `CAPX_TEMPERATURE` | `1.0` | LLM temperature |

## 排查顺序

1. `nvidia-smi` 是否正常；
2. `bash capx_scripts/check_capx.sh` 是否通过；
3. 8110 API proxy 是否在终端 A 运行；
4. 8114、8115、8116 是否被其他进程占用；
5. OpenRouter key 是否有效，是否 401/429；
6. Hugging Face 是否已接受 SAM3 gated access；
7. GitHub/PyPI/HF 下载是否需要代理。

更详细的说明见：

```text
capx_scripts/README_CAPX_CN.md
```

CaP 与触觉记忆结合的设计说明见：

```text
README_TACTILE_CAP_CN.md
```
