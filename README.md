# T-CaP / CaP-X 最小复现脚本

这个仓库包含 CaP-X 复现脚本和 OpenTacBench 接入。仓库保存代码、配置、少量冻结触觉标定参数及评估结果；Python 环境、大模型权重、缓存、原始轨迹、运行输出和 API token 保留在数据盘。

## OpenTacBench Shadow Hand 钢琴

另一台服务器运行五维 DIGIT 力估计 smoke，请先阅读[当前进展与迁移运行文档](docs/shadow-piano-handoff.md)。文档包含已上传的五维模型／评估结果、匹配传感器配置、环境条件、路径设置、单 seed 命令和审计方式。

钢琴代码使用父仓库记录的 cap-x commit；不要使用下方旧 Cube Stack 流程的 `submodule update --remote` 来选择钢琴版本。以下保留原 Cube Stack 复现说明。

### 当前版本：代码补丁闭环与触觉 key（2026-10-28）

**实现代码补丁闭环框架，正在实验触觉key是否有用。** 本次更新位于t-cap的
`feat/opentac-piano-tension-integration`，对应cap-x的`feat/capx-piano-tension-integration`。
精确版本以父仓库提交的子模块指针为准；同步后执行 `git submodule update --init cap-x`。

触觉key用于在公开错误触发代码修复时查找历史执行经验：

| 通路 | 表示 | 当前作用 |
|---|---|---|
| 即时 | 5D：深度形变均值＋三个像素比例＋面积变化率 | 保留冻结力估计器和即时触觉检索 |
| 时序基线 | window4，16帧×4D标准化展开为64D并L2归一化 | 最近0.5秒触觉过程的检索key |
| 学习型时序 | tactile，32D | 编码连续深度形变与有效掩码 |
| 触觉＋动作时序 | tactile_action，32D | 额外编码4D动作目标和4D实际手部状态 |

窗口按物理时间构造16个30Hz采样点，不直接截取60Hz观测的最后16条，不跨reset或补造缺失值。
即时与时序并行，时序不替代5D测力。只在发生公开错误、准备重新生成/修复代码时检索，
正常执行持续记录。检索按传感器、动作阶段、黑白键/轻重、编码器与预处理版本隔离，
沿触觉片段→实际函数调用→历史补丁→公开验证结果提供经验；真实力与原生评分仅用于私有审计。

局部修复经验可以被再次检索，整段策略是否允许默认复用则独立审核。目前已跑通历史释放
补丁的检索、执行和新seed继承，但单次对照存在无历史组补丁格式失败，尚未证明触觉key
相对无历史或语言检索带来稳定收益。完整设计与代码入口见
[cap-x README：触觉key与代码补丁闭环](cap-x/README.md)，结果见
[钢琴实验账本](cap-x/docs/opentac-shadow-piano-experiment-ledger.md)。

继续沿用 `./run_responses`，配置为
`env_configs/opentac/play_piano_shadow_digit_evidence_memory.yaml`。在新服务器上设置
`CAPX_SHADOW_TRAJECTORY_RUN`（冻结编码器及归一化目录）、`CAPX_SHADOW_EVIDENCE_ROOT`
（公共证据库）、`CAPX_SHADOW_PRIVATE_AUDIT_ROOT`（私有审计）以及实际OpenTacBench/Conda路径。
编码器权重、原始轨迹、运行视频和secrets不会随Git上传，需要独立迁移。

## 仓库结构

```text
t-cap/
  cap-x/                 # CaP-X 官方仓库，作为 git submodule 固定版本
  capx_scripts/          # 本仓库提供的一键安装、检查、API proxy 和评测脚本
  README.md              # 当前说明
```

查看当前父仓库固定的 `cap-x` commit：

```text
git ls-tree HEAD cap-x
```

同时 `.gitmodules` 记录了 `cap-x` 开发分支：

```text
branch = feat/tac
```

## 1. 克隆仓库

不要使用 `--recursive`，否则可能递归下载 CaP-X 的全部 third_party 子模块。先只初始化顶层 `cap-x` 子模块：

```bash
git clone git@github.com:flyingc2004/t-cap.git
cd t-cap
git submodule update --init cap-x
```

后续 `setup_capx.sh` 只会初始化 Cube Stack 必需的三个 CaP-X nested submodules：

```text
capx/third_party/robosuite
capx/third_party/sam3
capx/third_party/contact_graspnet_pytorch
```

如果希望把 `cap-x` 更新到 `.gitmodules` 中记录的 `feat/tac` 分支最新提交：

```bash
cd t-cap
git submodule update --remote cap-x
```

注意：外层 `t-cap` 为了保证可复现，仍然记录 `cap-x` 的具体 commit。更新到最新 `cap-x/feat/tac` 后，如果要让别人 clone 时也拿到这个新版本，需要提交一次外层 submodule 指针：

```bash
git add cap-x
git commit -m "Update cap-x submodule"
git push
```

如果已经 clone 了仓库，想同步当前外层 `t-cap` 记录的精确 `cap-x` commit：

```bash
git pull
git submodule update --init cap-x
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
