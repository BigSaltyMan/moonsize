# moonsize 开发日志

给验收者的一页说明：关键技术决策、AI 在其中的角色、参考来源。每一条都对应仓库里的证据，可以逐条复核。

## 1. 项目周期与入口

仓库建于 2026-10-02，第一个版本 0.1.0 于 10-03 发布，10-05 发布 0.3.0。全部提交位于公开仓库的默认分支 `main`，每个提交只做一件可描述的事。模块入口见 `moon.mod`；`moon check --target native --deny-warn`、`moon test`、`moon build --target wasm` 是本地与 CI 共用的门禁。

## 2. 关键决策

**符号 mangling 规则靠反推，且不猜。** MoonBit 未公开 name 段的命名规则，所以规则来自真实构建产物的实测反推（`moonc` 0.1.20260920，`wasm` 后端），过程与已知边界写在 `README.md` 的 "Symbol names" 一节。解码失败时返回原符号而不是编一个像样的名字 —— 报告里出现假名字比出现原始符号更糟。

**分析模型参考 Twiggy，实现独立。** 体积归因到函数、函数按包聚合、从模块根出发判定可达性，这三个选择来自 Rust 生态的 [Twiggy](https://github.com/rustwasm/twiggy)（MIT/Apache-2.0）。本项目未移植其源码，仅采用同一套分析模型；差异见 `README.md` 与"已知边界"一节。

**调用图宁多不少。** `call x` 是精确边；`call_indirect` 无法静态确定目标，因此对元素段放进该表的每个函数都连一条保守边（`wasm.mbt`）。多算一个函数的后果是体积被高估，少算一条边的后果是"把这个函数报成死代码"—— 后者是本工具最不该犯的错。

**Retained Size 用虚拟根加支配树。** 加一个虚拟根连到所有真实根，就能一次算出全部函数的 retained size，而不是每个函数各跑一次可达性；调用图里的环由不动点自然收敛（`graph.mbt`）。支配树与更弱的"唯一前驱"启发式之间的差别，被固定成测试期望，避免后续有人把它改回去（见提交"记录支配树与唯一前驱启发式的差异"）。

**指令解码全表驱动。** 247 条操作码各带一个规范编码与长度（`opcodes.mbt`），未知操作码报错而非静默跳过 —— 静默跳过会让调用图少边，回到上一条的风险。测试逐条覆盖操作码表（`opcodes_wbtest.mbt`）。

**HTML 报告自包含。** ECharts 内联进生成的单文件报告（`assets/echarts.min.js`，版本与校验和见 `assets/README.md`），因此 `--html` 的输出可以离线打开、可以转发。发布包通过 `.moonignore` 排除生成好的示例报告，避免为一张截图让每个 `moon add` 多下 1.2 MB。

**库只做计算，不做 I/O。** 解析、分析、报告渲染都不读写文件，退出码由调用方决定（`cmd/main/main.mbt` 是唯一碰文件系统的包）。这样全部核心逻辑都能在没有进程的前提下被白盒测试覆盖，也让库调用方可以自己决定失败语义。

**公开 API 按"外部可用"来设计。** `Options` 是只读类型，外部无法构造，因此 0.3.0 补上了 `Options::default(path)` —— 在此之前，凡是接收 `Options` 的 API 对依赖本模块的程序都不可用。这类问题包内测试发现不了（同包内可见私有成员），所以另设 `_probe/`：一个把本模块当库用的可执行包，走完 `parse_module → analyze → render_*` 并读取 `Analysis` 的每个公开字段。它是模块的一部分，默认的 `moon check` 就会检查它，等于把"公开 API 外部可用"变成 CI 第一步的回归。

## 3. 测试体系

三层，各管一件事：单元级白盒测试覆盖解析、操作码表、调用图、报告文本（137 个用例，`*_wbtest.mbt`）；契约级测试锁住默认值（`Options::default` 与命令行缺省值必须一致）；`_probe/` 锁住包外可用性。CI 覆盖格式化、`--deny-warn` 检查、测试，以及体积预算（含"门禁真的会触发"的反向验证）。

## 4. AI 工具的角色

AI 工具参与了实现、测试与文档的编写，以及符号规则的探针脚本和这份日志的整理。参赛者对以下内容负责并有据可查：项目目标与范围（体积归因、调用图、Retained Size、体积预算）、技术路线（见第 2 节）、代码质量与边界（未知操作码报错、解码失败返回原符号、`call_indirect` 保守处理）、开源合规（见第 5 节）、以及全部测试的有效性。

验证方式是**以证据为准，而非以生成为准**：符号规则由真实构建反推而非按文档抄写；操作码表逐条对照规范编码；未实现或无法确定的情况选择报错或标注已知边界，而不是给出看起来合理的结果。任何无法被测试、示例或外部工具验证的输出，都不作为结论写进 README 或报告。

## 5. 参考来源与许可证

| 名称 | 用途 | 许可证 | 说明位置 |
|---|---|---|---|
| Twiggy | 分析模型参考（非代码移植） | MIT / Apache-2.0 | `README.md` |
| Apache ECharts 5.6.0 | HTML 报告绘图，内联于 `assets/echarts.min.js` | Apache-2.0 | `assets/README.md`（含版本、大小与 SHA-256） |
| `bikallem/compress` | gzip 压缩 | Apache-2.0 | `moon.mod` |
| `moonbitlang/x` | CLI 的文件与系统调用 | Apache-2.0 | `moon.mod` |
| `moonbitlang/core` | 内置 JSON 与 UTF-8 | Apache-2.0 | `moon.pkg` |

本项目采用 MIT 许可证（根目录 `LICENSE`）。示例二进制 `examples/fib.wasm` 由仓库内 `examples/fib.mbt` 用本工具链编译生成，可重新生成（步骤见 `README.md` 的 "Regenerating the example"）。

## 6. 统一调用图诊断与 API 迁移（2026-10-15）

在尾调用修复 `07edf7b` 之后，完整性判断改用 `CallGraph.diagnostics`。新增公开 `GraphDiagnosticKind`（`NoStaticTableTargets`、`UnmodeledReferenceCall`）和 `GraphDiagnostic`（类别、完整 caller 索引、文件偏移、实际 opcode、可选 type/table 索引）。一个调用位置一条诊断，无候选表调用仍保留在 `unresolved_indirect`，但不重复计入总缺口数。`Analysis.unresolved_count` 保持原义，只计无静态候选的表调用。

本次识别 `call_ref`、`return_call_ref` 并报告尚未实现的目标分析，未实现引用数据流求解，也不根据相邻 `ref.func` 猜测目标。`scan_calls` 的 `CallKind` 增加 `Reference` 分支，携带类型索引和偏移；外部穷举匹配需要迁移。`ref.func` 仍不是调用。

报告 API 有意调整为 `render_graph_warning(graph)`、`render_dead_code(analysis, top)`、`render_retained(analysis, top)`。后两者不再接收分散的数据和可选警告计数，内部直接读取诊断，避免调用者遗漏警告。`analyze` 对建模缺口仍返回 `Ok(Analysis)`；计算结果依赖当前图模型，严格模式在写任何格式文件前以退出码 3 拒绝。

调用图 JSON 保留已有字段，新增 `schema_version: 1`、`graph_complete`、`modeling_scope`、`diagnostics`。诊断记录字段为 `code`、`caller`、`offset`、`opcode`、`type_index`、`table_index`；稳定代码为 `no_static_table_targets` 和 `unmodeled_reference_call`。无诊断时返回空数组，引用调用的表索引为 null。诊断按 caller、offset 排序，HTML 内嵌数据使用相同诊断结构；DOT 用图级标签携带警告。动态 table 和所有 Wasm 机制仍未完整建模，`graph_complete: true` 仅表示本期检测范围内未发现缺口。

验证从 158 项测试基线开始，先用公开 API 测试复现引用调用遗漏，再验证结构化诊断、各输出、严格模式和 Commit 1 的尾调用结果。本地 native 测试实际结果为 172 项通过、0 项失败。`scripts/test-tail-calls.sh` 保留原有 5 个进程场景；新增 `scripts/test-graph-diagnostics.sh` 覆盖 17 个进程场景，并用 Node.js/V8 验证 9 份合法 Wasm 样本、解析 JSON 断言字段，验证严格模式不会创建或覆盖报告文件。两个脚本都接入 CLI 构建后的 CI 步骤。目标提交的 Linux CI 成功记录取得后，才能标记远程验证完成。
