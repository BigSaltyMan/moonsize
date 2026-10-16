# Retained size 边界与重编译实测案例

日期：2026 年 10 月 16 日。用于回应十月黑客松初审中“保守引用图及逐段压缩模型不足以支撑精确删减收益承诺”的反馈。

moonsize 提供编译产物的体积归因、模型内可达性与支配关系，以及实际构建产物的比较。**不承诺删除某个源码函数后，文件或网络传输会精确减少 retained size 所示的字节。** 原申报书中的“删掉谁能省多少”“精确计算删除后的总大小”和“网络上真正昂贵的分布”应改为下述定义与验证流程，而不是仅在末尾附一条限制说明。

## 三种不同的量

| 量 | 定义 | 能说明什么 |
| --- | --- | --- |
| 模型 retained，R(f) | 在修改前固定的图、根和权重下，求 f 的支配子树，累加其中可达本地函数的编码大小，包含 f 自身 | 当前模型中向该支配节点归因的函数编码字节；用于定位依赖分支 |
| 重编译原始减量，ΔW | size(before.wasm) − size(after.wasm) | 指定源码改动、工具链及构建参数下，完整文件的实测差值 |
| 整文件 gzip 减量，ΔG | size(gzip(before.wasm)) − size(gzip(after.wasm)) | 相同压缩器配置下，两个完整文件 gzip 流大小的实测差值 |

R 的函数权重为 `FunctionStat.total_size`，包括函数体长度前缀、locals 和指令字节，不包括数据、名称、类型和其它段。`DIES` 是同一模型支配集合中其它本地函数的数量，不是实际编译器必定删除的函数数量。

支配树计算在输入图上的确定性，不等于输入图覆盖真实执行的全部关系，也不等于模拟了源码修改。删除图节点与修改程序是两种不同操作：源码改动还必须改写调用点，可能触发内联、常量折叠、死代码消除、索引重编号、LEB 编码长度、数据和元数据变化。R 不模拟这些过程，通常不能与 ΔW 或 ΔG 互换。

## 根与边的保守范围

直接调用和直接尾调用使用指令中的目标。间接调用使用已知静态 element 候选；引用调用、导入/导出表、运行时写表、未建模初始化等会产生诊断。非严格报告保留限制，严格模式对已识别缺口返回 3。

根包含导出函数、start 和所有 element 引用的函数。最后一项是保守策略，包括私有表、passive 和 declarative 段；它不证明每个根实际会执行。多余的根或候选可能减少可报告的死代码并改变支配关系。若存在漏边，又可能得出不同方向的误差，不能对 retained size 统一承诺全局上界或下界。

**`graph_complete == true` 和 `--strict` 返回 0 只表示当前检测范围内没有发现缺口。它们不证明模型最小、程序所有路径已验证，或 retained 等于实际删除收益。** 即使图没有诊断，报告仍显示 retained 与重编译、整文件 gzip 的边界。

## 实测环境与复现

本机快照：Windows x64、Node.js 24.18.0、moonc `0.10.13+cbb11c36f`、moon `0.1.20260915`。代码基线为 `e5833fe`；本次仅调整边界表述、案例及相应验证，不修改支配树算法和压缩算法。完整结果记录工作区状态、源码/CLI/脚本 SHA-256、每份 Wasm 的 SHA-256 和工具链版本。

```sh
moon build --target native --release
node scripts/demo-retained-boundaries.mjs _build/native/release/build/cmd/main/main.exe
```

脚本将所有工程和原始报告写入 `_build/retained-boundaries/`，不修改仓库示例。四份 MoonBit 源码在 [`examples/retained-boundaries/`](../examples/retained-boundaries/)，执行器在 [`scripts/demo-retained-boundaries.mjs`](../scripts/demo-retained-boundaries.mjs)。本机完整数值快照见 [`retained-boundaries-results.json`](retained-boundaries-results.json)。

每组 MoonBit 案例都在同一个工程路径内按 before → after → rollback 构建，两侧统一 `--target wasm` 和 `--no-strip`，分别测试 debug 和 release。`#inline(never)` 使被调查函数保留独立身份，避免把内联后的代码误当作仍有独立函数。`--no-strip` 是为了保留分析名称，这些数字不是默认生产发行产物的普遍结论。

脚本用 V8 验证模块，用 moonrun 实际执行 MoonBit 产物，确认移除的是可选输出、基础输出保持不变；rollback 恢复完整 Wasm 字节和运行输出。两侧功能有意不同：移除了可选功能，不能将其称为所有业务语义不变的自动优化。

## 案例一 可选分支及独占字符串

`unique-before.mbt` 的主循环输出基础结果并调用 `boundary_target`，后者调用 `boundary_leaf` 产生可选文本；after 移除该调用。辅助函数仍留在源码中，由编译器在产物中消除。下面均为实测，单位 B。

| 模式 | R(target) | Wasm before → after | ΔW | 整文件 gzip before → after | ΔG |
| --- | ---: | --- | ---: | --- | ---: |
| debug，保留名称 | 52 | 10,824 → 10,168 | 656 | 5,236 → 4,999 | 237 |
| release，保留名称 | 52 | 10,516 → 9,860 | 656 | 5,079 → 4,851 | 228 |

debug 中 target 自身 23 B，独占 leaf 29 B，模型合计 R=52、DIES=1。实际 code 段减少 67 B，data 段减少 408 B，name 段减少 179 B，function 段减少 2 B，共 656 B；还包括调用者编码和元数据变化，不能把 656 B 全部解释为被支配函数的编码。

所有这些 before 模块均无图诊断，strict 返回 0，但 **52 ≠ 656 ≠ 237**。同样的 R 在不同构建模式下还对应不同 ΔG。这直接反驳“无诊断时 retained 就是精确重编译/压缩收益”的说法。

## 案例二 共享依赖继续存活

`shared-before.mbt` 的主循环直接调用 `boundary_shared`，也调用 `boundary_target`；target 再调用 shared。after 只移除 target 调用，shared 的基础输出保留。

| 模式 | R(target) | DIES | Wasm before → after | ΔW | 整文件 gzip before → after | ΔG |
| --- | ---: | ---: | --- | ---: | --- | ---: |
| debug，保留名称 | 16 | 0 | 10,295 → 10,168 | 127 | 5,038 → 4,997 | 41 |
| release，保留名称 | 16 | 0 | 10,074 → 9,947 | 127 | 4,898 → 4,859 | 39 |

shared 存在从根绕开 target 的路径，不属于 target 的支配子树。脚本确认 shared 在 after 产物中仍然存在。debug 的 ΔW 由 code 27 B、name 99 B、function 1 B 构成；R 只统计 target 的 16 B，而不是这次源码改动的全部效果。

这说明支配模型仍有用途：它区分独占分支与共享依赖，辅助决定调查方向；实际节省多少要看重编译结果。

## 案例三 保守根与真实执行的区别

这是**手工编码的 Wasm 对照，不是 MoonBit 重编译案例**。before 有一个未导出的私有表，静态 element 引用 `boundary_target`；导出的 `run()` 只返回 42，从不读取或调用该表。after 去掉这个表、element 和该函数，两份模块执行 `run()` 都返回 42。

| 模型结果 | Wasm before → after | ΔW | 整文件 gzip before → after | ΔG |
| --- | --- | ---: | --- | ---: |
| R(target)=5，DIES=0，无诊断，strict=0 | 91 → 53 | 38 | 104 → 77 | 27 |

before 中该函数因为 element 引用被保守地作为根，因此不会列为死代码。此例没有宣称工具自动证明了“可安全删除”；行为等价仅针对这个人工构造、无其它宿主入口的 `run()` 契约，由执行器独立验证。它证明保守根与实际执行不是同一概念，strict 通过也不能支持精确收益承诺。

另有运行时写表的合法执行样本：初始化后 `run()` 返回 7，但静态图没有求解该 table 数据流，保留诊断、strict 返回 3。脚本把它记录为拒绝策略案例，不提供删除收益结论。

## 整文件压缩与传输成本

案例一 debug 的各段独立 gzip 合计为 **5,371 B**，实际整文件 gzip 为 **5,236 B**；after 对应 **5,145 B** 和 **4,999 B**。独立流合计减少 226 B，整文件 gzip 减少 237 B，两者并不相等。

独立压缩各段或函数会分别建立压缩流，并重复支付封装开销；整文件压缩还可利用跨范围的重复内容。因此不提供 `SHARE(GZIP)`，不把独立流大小相加作为文件传输大小，也不把局部独立 gzip 当作删除收益。

ΔG 仍只是指定压缩器配置下的 gzip 表示体大小变化，不是实际 HTTP/TLS 网络测量。服务可能选择 gzip、Brotli、其它配置或不压缩；缓存、响应头和传输协议开销也不在此测量内。实际部署成本需在目标服务配置下另行测量。

## 重新审核材料与检查标准

1. 报名表替换上述过强承诺，使用 [`october-proposal.md`](october-proposal.md) 的项目定位和边界表述。
2. README、CLI 帮助、retained 表格、HTML 和导出模型说明使用相同定义，诊断为空时也说明边界。
3. 提供源码、脚本、完整测量 JSON、原始文本/图报告、运行输出和 SHA-256。CI 重新执行性质断言，并上传 `retained-boundary-evidence`，不强制跨平台压缩数字相同。
4. 案例和“通过测试”不能替代真实业务的删改验证；每次准备删除候选时，明确业务变更、重编译、运行回归，再比较完整文件与目标压缩表示。

这些材料回应模型与承诺不一致的问题，是否通过重新审核由主办方根据更新后的申报范围和证据判断。
