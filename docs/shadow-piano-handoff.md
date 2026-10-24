# Shadow Hand＋DIGIT 钢琴：当前进展与跨服务器运行

更新日期：2026-10-24。本文用于在另一台已有 Isaac Sim／OpenTacBench 环境的服务器上
运行一条五维触觉力 CaP-X smoke。所有实验产物、环境和缓存放在该服务器的数据盘。

## 1. 当前完成到哪里

| 项目 | 当前状态 |
|---|---|
| 机器人与任务 | Franka 机械臂搭载 Shadow Hand，食指单指，OpenTacBench `arm_shadow_piano` |
| 触觉 | 单指 DIGIT，独立 Python 3.11＋TACTO 0.0.3，RGB 和模拟 depth 同步返回 |
| 视觉定位 | 初始清场后的 HEAD 图，公开 A0/C8 端点＋0.0235 m 白键间距辅助一次定位全部目标键 |
| 定位后续问 | 已保存键位，LLM 后续请求为纯文本，使用公开实际 X/Y、速度及触觉调整 |
| 动作频率 | 240 Hz 物理，每动作 4 个物理步，公开触觉／控制 60 Hz |
| 力估计 | 已接入独立五维模型：深度均值＋三个面积比例＋面积变化率，不输入关节状态 |
| 数据审计 | 50 条成功专家轨迹，40 seed 训练、10 seed 完整留出，五维比四维改善初触误差 |
| CPU 验证 | 33 项通过；946 帧回放中五维特征与离线提取误差为 0 |
| 五维 GPU smoke | 尚无有效任务结果；本机首次运行在 CUDA 初始化失败，未进入按键阶段 |
| 原四维实际运行 | 已有 4 物理步的 6/8 记录；旧配置曾达 7/8，配置不同，不能合并为五维结果 |
| 视频 | 支持按物理时间对齐的原生接触合成音频；它不等同于计分成功证据 |

OpenTacBench 源码、物理及逐音力／保持／释放判据未由此次接入修改。
当前 smoke 使用原生 `piano_continue_on_note_failure: true`：失败后继续尝试，最后统计八音成功数，
不是放宽逐音的力度判定。`piano_state` 用于执行进度和键位持久化；静态力标定与目前案例库
尚不能单独代表已经完成论文中的在线历史接触记忆。

### 当前 smoke 音序

Seed 为 3150，八次尝试依次为：

| 次序 | 音 | 力度 |
|---|---|---|
| 1 | E4 | light |
| 2 | F4 | heavy |
| 3 | C#4 | light |
| 4 | D#4 | heavy |
| 5 | D#4 | light |
| 6 | E4 | heavy |
| 7 | C#4 | heavy |
| 8 | F4 | light |

每音持音要求为 0.12 秒；模型完成八次尝试后提交 `capx_stop=True`／END，由原生任务最终判分。
当前配置固定此八音。自定义音序需要同步修改配置中的音符、力度、持音与任务提示词；
此接入没有实现 WAV／MP3 自动转谱。

## 2. 取得正确代码与五维结果

目标分支：

- t-cap：`feat/opentac-piano-tension-integration`
- cap-x：`feat/capx-piano-tension-integration`，实际运行以 t-cap 记录的子模块 commit 为准。

已有 t-cap 时先检查未提交改动；有改动时先保留，不执行会覆盖它们的切换操作。

```bash
cd /实际路径/t-cap
git status --short
git fetch origin feat/opentac-piano-tension-integration
git switch feat/opentac-piano-tension-integration
git pull --ff-only origin feat/opentac-piano-tension-integration
git -c 'url.https://github.com/.insteadOf=git@github.com:' submodule update --init cap-x
git ls-tree HEAD cap-x
git -C cap-x rev-parse HEAD
```

最后两个命令应显示同一个 cap-x commit。这里不使用 `submodule update --remote`：
`.gitmodules` 中的旧 `feat/tac` 名称不用于选择钢琴代码。也无需递归下载全部 third_party。

首次克隆：

```bash
git clone --branch feat/opentac-piano-tension-integration \
  https://github.com/flyingc2004/t-cap.git
cd t-cap
git -c 'url.https://github.com/.insteadOf=git@github.com:' submodule update --init cap-x
```

五维结果已随 cap-x 分发：

```text
cap-x/env_configs/opentac/shadow_digit_key_top_force_5d_area_rate.v1.json
cap-x/env_configs/opentac/config_digit_piano_0_2.v1.yml
cap-x/docs/results/shadow_digit_area_rate_20261024/comparison_report.json
cap-x/docs/results/shadow_digit_area_rate_20261024/models_offline_only.json
cap-x/docs/results/shadow_digit_area_rate_20261024/heldout_alignment.png
cap-x/docs/results/shadow_digit_area_rate_20261024/initial_contact_scatter.png
cap-x/docs/results/shadow_digit_area_rate_20261024/manifest.json
```

**运行冻结模型不需要复制 50 条原始 HDF5。** 此包包含模型、完整聚合评估与审计图，
不包含逐帧私有真实力、特征缓存或 API 凭据。若要重新训练，需要另行迁移原始公开深度轨迹
及私有标签；本机原位置记录在完整离线报告里，不能将其加入运行时 prompt。

## 3. 另一台服务器的环境条件

以下是本机已安装环境的记录，供核对，不要求为此升级另一台服务器的 Isaac Sim：

| 部分 | 本机记录 |
|---|---|
| Isaac 主环境 | Python 3.10，Isaac Sim 4.5.0.0 |
| Isaac Lab | 源码 tag v2.1.1；安装 distribution `isaaclab` 为 0.41.3 |
| PyTorch | 2.5.1+cu124 |
| 主环境 NumPy | 1.26.4 |
| OpenTacBench | `179bb8b5fe987f30ac17c407c5265b40c8f223a7`，含 Shadow 逐音继续尝试支持 |
| 独立 DIGIT 环境 | Python 3.11.15，TACTO 0.0.3，NumPy 1.23.5，PyOpenGL 3.1.7，pyrender 0.1.45 |

复用另一台机器已有 OpenTacBench checkout，检查 `env/tasks/arm_shadow_piano.py`、
`scripts/_piano_digit_assets.py` 等文件及版本；本指南不自动切换或修改其源码。
Shadow/DIGIT 启动入口不要求添加 TacEx 的 `PYTHONPATH`，也不需要启动 SAM 感知服务。
普通 Python 缺少 Kit 的 `omni` 不能据此判断 Isaac 任务未安装。

### 独立 TACTO 与原版资产

已有 `OpenTacBench/.cache/piano_tactile/digit/venv/bin/python` 时先检查版本并复用。
如果另一台机器尚未安装，下面是在数据盘建立新环境的例子；将下一节的路径变量先设好。
`DIGIT_INSTALL_ROOT` 与 OpenTacBench 的缓存链接应为尚未被其他项目使用的新路径。

```bash
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
export DIGIT_INSTALL_ROOT="$OPENTAC_DATA_ROOT/piano-tactile/digit"
mkdir -p "$DIGIT_INSTALL_ROOT"
python3.11 -m venv "$DIGIT_INSTALL_ROOT/venv"
"$DIGIT_INSTALL_ROOT/venv/bin/python" -m pip install \
  numpy==1.23.5 scipy==1.10.1 trimesh==3.23.5 omegaconf==2.3.0 \
  Pillow==10.4.0 imageio==2.37.0 pyglet==1.5.31 freetype-py==2.5.1 \
  networkx==3.4.2 six==1.17.0 PyOpenGL==3.1.7 pybullet==3.2.7 \
  opencv-python-headless==4.10.0.84
"$DIGIT_INSTALL_ROOT/venv/bin/python" -m pip install --no-deps \
  tacto==0.0.3 pyrender==0.1.45
"$DIGIT_INSTALL_ROOT/venv/bin/python" "$UNIVTAC_ROOT/scripts/_piano_digit_assets.py" \
  "$DIGIT_INSTALL_ROOT/assets"
mkdir -p "$UNIVTAC_ROOT/.cache/piano_tactile"
ln -s "$DIGIT_INSTALL_ROOT" "$UNIVTAC_ROOT/.cache/piano_tactile/digit"
```

`ln -s` 不带强制覆盖；若目标已存在，检查已有路径而不是删除它。
下载脚本固定原版 Meta 资产 revision 并校验 CAD／背景 SHA256。
TACTO 的 NumPy 依赖保留在独立环境，主 Isaac 环境继续使用自己的版本。
运行时加载的是仓库内已冻结的 `[0,2] N` 配置，不使用安装包默认 `[0,100]` 配置。

## 4. 设置本机路径与数据盘

下面 `/mnt/sdc/ljz` 只是另一台服务器路径的例子。替换为该机器已安装的位置：

```bash
cd /mnt/sdc/ljz/t-cap
export CAPX_DIR="$PWD/cap-x"
export UNIVTAC_ROOT=/mnt/sdc/ljz/OpenTacBench_capx
export CONDA_SH=/mnt/sdc/ljz/miniforge3/etc/profile.d/conda.sh
export CONDA_ENV_NAME=/mnt/sdc/ljz/opentacbench/conda-envs/UniVTAC
export CAPX_PYTHON="$CONDA_ENV_NAME/bin/python"
export OPENTAC_DATA_ROOT=/mnt/sdc/ljz/opentacbench

export RUN_ROOT="$OPENTAC_DATA_ROOT/capx-runs"
export CAPX_RUN_ROOT="$RUN_ROOT"
export CAPX_CACHE_ROOT="$OPENTAC_DATA_ROOT/capx-cache"
export PIP_CACHE_DIR="$CAPX_CACHE_ROOT/pip"
export CAPX_SHADOW_PRIVATE_AUDIT_ROOT="$OPENTAC_DATA_ROOT/capx-private-audits/shadow_piano_visual_force_v1"
export UNIVTAC_HOME="$OPENTAC_DATA_ROOT/kit-home"
export UNIVTAC_XDG_CACHE_HOME="$OPENTAC_DATA_ROOT/kit-cache"
export UNIVTAC_XDG_DATA_HOME="$OPENTAC_DATA_ROOT/kit-data"
export UNIVTAC_XDG_CONFIG_HOME="$OPENTAC_DATA_ROOT/kit-config"
export TMPDIR="$OPENTAC_DATA_ROOT/tmp"
mkdir -p "$RUN_ROOT" "$TMPDIR"
```

主 Conda 环境需要已有 OpenTacBench／Isaac 与 CaP-X 依赖；本指南不是从零安装 Isaac 的脚本。
将该机器自己的 Responses API 参数放在 `t-cap/.capx_secrets.env`：
`CAPX_API_BASE_URL`、`CAPX_MODEL`、`CAPX_API_KEY`。`run_responses` 自动读取此文件。

## 5. 启动前的两项验证

无需 GPU 验证标定包：

```bash
python3 "$CAPX_DIR/scripts/opentac/check_shadow_digit_bundle.py"
```

预期 `Verified 6 bundle files`，传感器配置 SHA256：

```text
2c4e762965a06d1b38fbd6a54d638087ba2fa057dace69bdb77c741cb82f4208
```

然后实际检查指定卡的 CUDA；`nvidia-smi` 能列卡不代表 CUDA 可计算：

```bash
nvidia-smi
CUDA_VISIBLE_DEVICES=0 "$CAPX_PYTHON" - <<'PY'
import torch
print(torch.__version__, torch.cuda.is_available())
assert torch.cuda.is_available()
x = torch.tensor([1., 2., 3.], device='cuda:0')
print(torch.cuda.get_device_name(0), float((x*x).sum().item()))
PY
```

最后应得到计算结果 `14.0`。本机目前 8 张卡均提示 `GPU requires reset`，
`cuInit=100 CUDA_ERROR_NO_DEVICE`，所以未能继续五维 GPU 试验；此硬件状态不代表另一台服务器也有问题。

## 6. 单 seed、单 trial 的运行命令

在同一个已经设置上述环境变量的终端中执行，GPU 编号由调用者指定：

```bash
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
CONFIG_PATH=env_configs/opentac/play_piano_shadow_digit_visual_force_5d_60hz_smoke.yaml \
GPU=0 MODE=smoke TRIALS=1 REPEATS=1 \
MAX_TRIAL_RETRIES=0 MAX_TOKENS=8192 \
TRIAL_TIMEOUT_SECONDS=7200 PROCESS_TIMEOUT_SECONDS=7800 \
CAPX_DISABLE_PROXY=1 PYTHONUTF8=1 LANG=C.UTF-8 LC_ALL=C.UTF-8 \
RUN_LABEL=shadow_5d_area_rate_4phys_seed3150_gpu0 \
./run_responses
```

启动日志应出现：

```text
force calibration=shadow_digit_key_top_force_5d_area_rate.v1 features=5 area_rate_window_physics_steps=8
```

另外核对 TACTO 配置 SHA256 与上节一致。若出现旧 `4d.v1`，检查 CONFIG_PATH、
CAPX_DIR 与父仓库子模块指针，先不要将该次结果当作五维实验。

## 7. 五维含义与已测结果

设有效像素的模拟深度差为 `d=abs(reference_depth-depth)*1000`，单位 mm：

| 顺序 | 名称 | 定义 |
|---|---|---|
| 1 | mean_mm | 有效像素 d 的均值 |
| 2 | area_gt_0p01mm | d>0.01 mm 的像素比例 |
| 3 | area_gt_0p05mm | d>0.05 mm 的像素比例 |
| 4 | area_gt_0p2mm | d>0.2 mm 的像素比例 |
| 5 | area_gt_0p05mm_rate_per_s | 第三维与 8 物理步前的差除以 1/30 秒 |

不输入手指弯曲度、腕部高度、真实力、目标轻重音或评分。
黑白键分别建模；黑白键类型由 agent 指定的目标音决定。
适配器在每次原生动作后采样历史，重复估力调用不推进时间，代码重新生成保留历史，
reset 清空。历史不足为 `insufficient_history`，OOD 不给牛顿值，输出不裁剪。

50 条专家轨迹中，seed 3100–3139 训练、3140–3149 留出。以下均为留出 MAE（N）：

| 范围 | 四维 | 五维 |
|---|---:|---:|
| 接触帧整体 | 0.00583 | 0.00274 |
| 初触阶段 | 0.02419 | 0.00475 |
| 白键重音初触 | 0.04005 | 0.00693 |

10 个留出 seed 的接触 MAE 都改善，专家留出集两组 OOD 均为 0。
释放阶段 P95 略升，且无接触原始回归误差增加；安全门控不将负预测作为有效牛顿值。
完整分组、偏差、RMSE、P95 与延迟见 `comparison_report.json`。

这些是 30 Hz 成功专家路径的离线结果，尚不能证明 CaP-X 初触姿态的泛化。
新增第五维也不会自动解除原四维特征越界。TACTO 外观由接触几何和 PhysX 力共同生成，
因此这是模拟触觉图像的力反演，不是独立指尖测力计验证。

## 8. 每次运行需要带回哪些结果

公开运行目录为 `$RUN_ROOT/<RUN_LABEL>_smoke_rep1_<UTC时间>/`：

- `run.log`、生成的 `code.py`、`summaries.txt`、每轮 prompt 与视频。
- 查找 `PIANO_ARRIVAL`、`PIANO_FORCE_TRIM`、八条 `PIANO_NOTE`、END 和退出码。
- `PIANO_STOP OOD_REPROBE` 表示同音首次初触 OOD 检查点；后续不重复已经结算的音。

运行结束后日志中的 `native piano audit=...` 指向独立私有目录：

- `shadow_piano_native_audit_summary.json`：原生成功音数、尝试数、逐音事件与 END。
- `shadow_force_estimates_private_audit.jsonl`：同一步估计／真实力、五维特征、越界维度和动作。
- `shadow_piano_physics_trace.jsonl`：240 Hz 原生轨迹，用于检查采样之间是否真的持续达标。
- `shadow_digit_ood_depth_*.npz`：发生 OOD 时的原始深度与参考深度。
- `shadow_force_estimate_vs_native.png`：估计与真实力对齐图。

这些私有文件用于试验结束后的人工审计，不输入 LLM、提示词或公开记忆。
公开保持信心并不证明中间 240 Hz 物理步全部达标；最终成功以原生判分为准。
退出码 1 可能是任务部分计分，也可能是启动失败，需要结合原生摘要与日志区分。

## 9. 下一步与论文记录

第一步是在可用 GPU 上取得一条有效五维 smoke，再判断：定位、实际到位、初触力估计、
连续保持和释放各自是否正确。对早期 OOD 逐维核对，不能靠放宽门槛或 prompt 猜牛顿数。
若 CaP-X 姿态下仍失准，补采该姿态的 60 Hz 深度与同步私有真实力，再按完整 episode 留出评估。

现有实验账本在 `cap-x/docs/opentac-shadow-piano-experiment-ledger.md`，包括逐次成功音数和动作数。
新服务器的结果可用下面脚本生成独立账本，保留本仓库历史文档：

```bash
python3 "$CAPX_DIR/scripts/opentac/build_shadow_piano_experiment_ledger.py" \
  --runs-root "$RUN_ROOT" \
  --audit-root "$CAPX_SHADOW_PRIVATE_AUDIT_ROOT" \
  --output "$RUN_ROOT/shadow-piano-experiment-ledger.md"
```

完整离线报告在 `cap-x/docs/opentac-shadow-digit-area-rate-ablation-20261024.md`；
历史失败案例在 `cap-x/docs/opentac-shadow-piano-failure-skill-library.md`；
本机 CUDA 故障记录在 `cap-x/docs/opentac-shadow-5d-startup-diagnostic-20261024.md`。
