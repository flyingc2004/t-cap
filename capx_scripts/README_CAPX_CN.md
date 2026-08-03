# CaP-X 最小复现说明

这套脚本只复现官方 Robosuite Cube Stack 单轮 Code-as-Policy 流程。LLM 通过 OpenRouter API 调用，本机只运行 Robosuite、SAM3、ContactGraspNet 和 PyRoKi，不安装本地语言模型，也不安装 LIBERO-PRO、BEHAVIOR 或 CaP-RL。

## 文件与目录

- CaP-X 仓库：`/mnt/a/ljz/tabero/cap-x`
- Python 环境：`/mnt/a/ljz/tabero/cap-x/.venv`
- 缓存：`/mnt/a/ljz/tabero/cap-x-cache`
- 运行日志和视频：`/mnt/a/ljz/tabero/capx-runs`
- 临时 OpenRouter key：`/dev/shm/$USER/capx-secrets/openrouter.key`

所有缓存都位于 `/mnt/a`，临时文件位于 `/dev/shm`，不会使用根分区的默认缓存。脚本不会调用 `sudo`。

## 1. 安装

```bash
bash /mnt/a/ljz/tabero/capx_scripts/setup_capx.sh
```

该命令会执行以下操作：

1. 检查 Git、uv、NVIDIA 驱动、`libGL.so.1` 和 `libEGL.so.1`。
2. 拉取官方 `capgym/cap-x`，以及 Cube Stack 必需的 `robosuite`、`sam3` 和 `contact_graspnet_pytorch` 子模块。
3. 用 uv 安装用户态 Python 3.10。
4. 创建 `.venv`。
5. 执行 `uv sync --extra robosuite --extra contactgraspnet`。

如果仓库已经存在，脚本不会执行 `git pull`、`git reset` 或覆盖本地修改。若系统缺少 `uv`，先在用户目录安装：

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source "$HOME/.local/bin/env"
```

## 2. 静态检查

```bash
bash /mnt/a/ljz/tabero/capx_scripts/check_capx.sh
```

检查应满足：

- Python 是 3.10；
- `capx`、`mujoco`、`robosuite`、`OpenGL.EGL`、`torch` 和 `contact_graspnet_pytorch` 均能导入；
- PyTorch 能看到一张 RTX 4090；
- 默认使用物理 GPU 7；
- 端口检查只报告状态，不会结束进程。

切换 GPU：

```bash
CAPX_GPU=3 bash /mnt/a/ljz/tabero/capx_scripts/check_capx.sh
```

## 3. 准备 SAM3 权限

CaP-X 默认的非特权 Cube Stack 配置需要 SAM3。先在浏览器中申请并接受 SAM3 checkpoint 的 Hugging Face 访问协议：

- <https://huggingface.co/facebook/sam3>

评测脚本会隐藏提示输入 Hugging Face token。token 只进入当前脚本进程的环境变量，不写入用户目录。也可以在运行前临时设置：

```bash
read -r -s -p "Hugging Face token: " HF_TOKEN
echo
export HF_TOKEN
```

运行完成后清除：

```bash
unset HF_TOKEN
```

不要在共享服务器上执行 `hf auth login`，否则 token 会被持久保存。

## 4. 启动 OpenRouter API 代理

在终端 A 运行：

```bash
bash /mnt/a/ljz/tabero/capx_scripts/run_capx_api.sh
```

脚本会隐藏提示输入 OpenRouter API key。key 只写入 `/dev/shm`，权限为 `600`；按 `Ctrl-C` 退出代理后自动删除。不要把 token 直接写在命令行里。

默认 endpoint：

```text
http://127.0.0.1:8110/chat/completions
```

如果 8110 已被占用，可同时修改两个终端使用的端口：

```bash
CAPX_PROXY_PORT=8120 bash /mnt/a/ljz/tabero/capx_scripts/run_capx_api.sh
```

## 5. 单条烟测

保持终端 A 的代理运行，在终端 B 执行：

```bash
bash /mnt/a/ljz/tabero/capx_scripts/run_capx_cube_stack.sh smoke
```

`smoke` 默认参数：

- 1 trial；
- 1 worker；
- 不录视频；
- `google/gemini-3.1-pro-preview`；
- GPU 7。

第一次运行会下载 SAM3 等模型权重，因此明显慢于后续运行。

## 6. 十条快速评测

单条烟测没有 API、CUDA、MuJoCo 或感知服务错误后执行：

```bash
bash /mnt/a/ljz/tabero/capx_scripts/run_capx_cube_stack.sh quick
```

`quick` 默认运行 10 trials、5 workers 并录制视频。每次运行使用独立目录：

```text
/mnt/a/ljz/tabero/capx-runs/cube_stack_quick_<UTC时间>/
```

其中 `run_config.txt` 保存配置和 CaP-X commit，`evaluation.log` 保存完整日志，`outputs/` 保存 CaP-X 输出、生成代码和视频。

官方快速回归的参考线是 10 条中至少成功 2 条。低于 2 条但完整生成、执行和仿真链路均正常时，说明工程复现已经跑通，但策略效果没有达到官方参考值。

## 参数覆盖

```bash
CAPX_GPU=3 \
CAPX_MODEL=google/gemini-3.1-pro-preview \
CAPX_TRIALS=3 \
CAPX_WORKERS=1 \
CAPX_RECORD_VIDEO=False \
bash /mnt/a/ljz/tabero/capx_scripts/run_capx_cube_stack.sh smoke
```

常用变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `CAPX_GPU` | `7` | 使用的物理 GPU 编号 |
| `CAPX_MODEL` | `google/gemini-3.1-pro-preview` | OpenRouter 模型 ID |
| `CAPX_PROXY_PORT` | `8110` | 本地 API proxy 端口 |
| `CAPX_TRIALS` | 模式默认值 | trial 数量 |
| `CAPX_WORKERS` | 模式默认值 | 并发 worker 数量 |
| `CAPX_RECORD_VIDEO` | 模式默认值 | 是否录制视频 |
| `CAPX_TEMPERATURE` | `1.0` | LLM temperature |

## 常见问题

### Hugging Face 401/403

确认 Hugging Face 网页上已经接受 SAM3 权限，并重新输入具有 read 权限的 token。不要使用 `hf auth login` 持久登录。

### OpenRouter 401

API key 无效或已失效。停止代理后重新启动，并在隐藏提示中输入新 key。

### OpenRouter 429

降低并发后重试：

```bash
CAPX_WORKERS=1 bash /mnt/a/ljz/tabero/capx_scripts/run_capx_cube_stack.sh quick
```

同时检查 OpenRouter 额度和该模型的速率限制。

### 8114、8115 或 8116 被占用

这三个端口分别用于 SAM3、ContactGraspNet 和 PyRoKi。脚本只报告监听状态，不会杀进程。CaP-X 会复用已存在的服务；如果它们不是本次 CaP-X 启动的服务，应先由进程所有者停止，再重新运行。

### CUDA 不可见

先在普通 SSH shell 运行：

```bash
nvidia-smi
```

然后确认选择的 GPU 存在且空闲：

```bash
nvidia-smi -i 7
```

### EGL 或 OpenGL 缺失

脚本不会使用 sudo。把检查结果交给管理员，让管理员安装 Ubuntu 的 `libegl1` 和 `libgl1`。

### `fetch-pack`、`early EOF` 或模型下载中断

安装脚本默认使用 HTTP/1.1、浅克隆，并串行下载三个 Cube Stack 必需子模块。它不会继续下载 LIBERO-PRO、BEHAVIOR、cuRobo 或 VeRL。网络恢复后直接重新运行 `setup_capx.sh`；已有完整主仓库、Python 环境和下载缓存都会被复用。

如果本地代理不稳定，可以先关闭代理后重试直连：

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
bash /mnt/a/ljz/tabero/capx_scripts/setup_capx.sh
```

如果必须使用代理，确认代理仍在监听后再运行。也可以增加重试次数：

```bash
CAPX_GIT_RETRIES=6 bash /mnt/a/ljz/tabero/capx_scripts/setup_capx.sh
```

### `ModuleNotFoundError: No module named 'mujoco'`

这说明 `.venv` 只创建了 Python 壳，依赖同步没有完整完成。不要重拉仓库，直接修复当前环境：

```bash
bash /mnt/a/ljz/tabero/capx_scripts/repair_capx_env.sh
bash /mnt/a/ljz/tabero/capx_scripts/check_capx.sh
```

## 官方资料

- CaP-X：<https://github.com/capgym/cap-x>
- CaP-X 配置说明：<https://github.com/capgym/cap-x/blob/main/docs/configuration.md>
- OpenRouter key：<https://openrouter.ai/keys>
