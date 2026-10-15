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

## 7. u32 LEB128 与读取边界（2026-10-15）

在 `6a9670b` 的 172 项测试、22 个 CLI 场景基线上，先增加公开 API 回归，复现第五字节非法高位将长度截断为零，以及空 start 段借用下一段字节的问题。`Reader::read_u32_leb` 改为 `Result[UInt, WasmError]`，完整保留 u32 范围；第五字节先检查高位及 continuation bit，再参与移位，最多读取五字节，保留合法非最短编码。所有长度、计数、索引和 `Array[Int]` 操作数经内部 `read_u32_as_int` 检查后转换，当前可表示范围为 `0..2147483647`。超出范围的合法编码返回 `ValueOutOfRange(offset, UInt)`，与 `LebOverflow(offset)` 编码错误区分。

Reader 增加 `[start, end)` 范围和 `new_range(data, start, length)`；构造、定位及切片前先检查负数和剩余长度，避免溢出。`seek` 现在返回 `Result[Unit, WasmError]`，失败不移动游标；`read_bytes` 同样保证失败不移动。新增 `InvalidReadRange(offset, length, start, end)`。错误使用绝对偏移，`remaining()` 为 `end - pos`。

段 payload、函数体和 name 子段使用独立范围；locals、指令操作数、element 常量表达式复用有界指令解码器。custom 段外层名称截断会报错；内部可选 name 元数据保留已读名称并在本子段范围内停止。导入基数与本地函数编号的相加先检查范围；计数不触发巨大预分配。signed LEB 和固定宽度读取仅同步边界，完整数值宽度设计不在本次范围，版本、段顺序、重复段和完整类型验证也未新增。

新增 Reader/LEB 单元测试、段与函数体跨界回归、公开 API 黑盒测试。新增 `scripts/test-parser-boundaries.sh`，本地通过 54 个进程场景，使用 Node.js 为每次 CLI 调用设置五秒超时并区分超时、崩溃与预期退出码。V8 交叉确认 19 个畸形完整模块和 4 个合法完整模块（含非最短编码、原始尾调用、引用调用和正常示例）；Reader 专用与可选元数据测试不作为完整模块送去比较。合法大 u32 作为 Reader 值成功返回，不能因相应畸形模块被验证器拒绝就将编码本身称为非法。

本地 native 测试实际结果为 206 项通过、0 项失败；三个过程级脚本合计 76 个场景，保持前两个提交的 retained、死代码和统一诊断行为。解析失败（含实现范围错误）返回输入错误码 `1`，加 `--strict` 仍为 `1`，不生成或覆盖报告文件；调用图分析缺口仍按原规则处理。CI 在现有两个脚本后追加新脚本；目标提交推送并取得 Linux CI 成功记录后才能标记远程验证完成。

## 8. Wasm 版本与基础段结构（2026-10-15）

在 `c444a48` 的 206 项测试、76 个 CLI 场景基线上，先用三个公开接口测试复现版本 `2`、重复 type 段被接受，以及 `analyze` 信任旧段表而漏掉实际输入乱序的问题；修复前这三个测试均失败。现在 `parse_module` 在魔数之后、解释段之前检查 Core Wasm 二进制版本，仅接受 `1`。错误保留偏移 `4` 与原始 `UInt` 值，全 `FF` 显示为 `4294967295`。

标准段只允许出现一次；重复或乱序错误指向当前违规段的 id 字节。顺序独立于 section id：Type、Import、Function、Table、Memory、Tag、Global、Export、Start、Element、DataCount、Code、Data，依据 [Core 二进制模块规范](https://webassembly.github.io/spec/core/binary/modules.html)。custom 段可同名重复、穿插出现，不改变顺序状态。

新增内部 `wasm_structure.mbt`，读取 function 段全部本地类型索引并完整消费 payload；code 段与公开 `parse_code_section` 复用同一个有界长度遍历器，逐个验证函数体长度，再检查剩余字节。两段缺失分别按零项处理，本地声明数必须等于函数体数，导入函数不参与比较。结构检查不构建调用图，也不分配函数体记录。`analyze(data, parsed)` 为兼容保留参数，但重新解析实际字节，避免旧段表或被修改的段表绕过检查；当前文件与 baseline 都先完成 `parse_module`，不会先打印半份报告。

公开解析函数签名保持不变，`WasmError` 新增 `UnsupportedVersion(offset, UInt)`、`DuplicateSection(offset, kind)`、`InvalidSectionOrder(offset, kind, previous)`、`FunctionCodeCountMismatch(offset, kind, declarations, bodies)`、`TrailingSectionBytes(offset, kind)`。外部穷举匹配需要处理这些分支；`.mbti` 与修复前的比较仅有这五项扩展。数量错误优先指向 code 段，缺失时指向 function 段；多余字节指向第一个未消费位置。输入结构错误统一返回 `1`，`--strict` 不改变它，也不将它转换为图缺口诊断。

新增白盒与公开 API 测试，覆盖版本、标准段重复、Tag/DataCount 顺序、custom 插入、缺失/空段与数量矩阵、导入索引、payload 完整消费及旧元数据。三处既有畸形测试改为断言解析阶段更早返回的同一越界错误，仍保留底层函数体解析器的边界断言。Commit 1 的 39 字节尾调用 retained `8`、Commit 2 引用诊断和 Commit 3 合法非最短编码继续通过。本地 native 测试为 **226 项通过、0 项失败**。

新增 `scripts/test-module-structure.sh`，通过 **235 个进程场景**，检查普通/严格模式、当前文件/坏 baseline、精确退出码、无正常表格或图警告，以及 JSON/DOT/HTML 新文件与已有文件保护。每个 CLI 调用有五秒超时，超时、崩溃、启动失败均不当作预期输入错误。Node.js/V8 独立验证 20 个畸形完整模块和 11 个合法完整模块；本机具备 Tag 验证能力，Tag、DataCount、同名 custom、导入函数和真实 MoonBit 示例均通过。CI 保留前三个脚本并追加该脚本；四个脚本合计 311 个进程场景。

本工具执行体积分析所需的基础结构检查，尚未提供完整的 WebAssembly 类型和指令语义验证。类型/调用索引合法性、指令栈类型及动态 table 完整性继续单独处理。后续提交 `53331c6` 修复 CI 的工具链安装和依赖初始化，并取得 [Linux CI 成功记录](https://github.com/BigSaltyMan/moonsize/actions/runs/38730438266)：检查、测试、四个过程级脚本和体积预算任务均成功。

## 9. 同名 custom 段的基线比较（2026-10-15）

在 `53331c6` 的 226 项测试、311 个 CLI 场景基线上，先通过公开接口复现 18 字节模块 `0061736d0100000000020178000401780000` 的自比错误：两个同名 `x` 段分别占 4、6 字节，旧实现都匹配 baseline 的第一个段，输出两行并出现虚假的 `+2 (+50.0%)`。新增测试在修复前失败，修复后只输出一行 `10 → 10`，差值为零。

`runner.mbt` 用内部 `SectionKey` 区分标准段 id 和 custom 完整名称，比较键不依赖显示标签。名称不截断、不清理空白、区分大小写；空名称及 Unicode 名称保留，custom `code` 与标准 code 分开。baseline 和 current 分别按键汇总 `total_size`，再合并键集合，每组一行；新增或删除的组缺失侧为零，不按出现位置或实例大小配对。

体积包含每个段实际占用的 id、payload 长度 LEB、全部 payload 以及 custom 名称编码。同名段重复承担的头部开销和合法非最短编码都计入。比如 baseline 的 `x` 为 `4 + 6`，current 为 `5 + 8`，输出 `custom (x): 10 → 13, +3`。排序固定为 current 总大小降序、baseline 总大小降序、标准段二进制顺序后接 custom 名称的 `String::compare` 顺序，不依赖 Map 遍历或文件排列。

`total` 仍为实际文件大小，分组两侧之和各加八字节头部等于文件总大小，各组差值之和等于 total 差值。组间增减可以抵消；体积相同不表示内容相同。`--max-size` 配合 baseline 仍限制文件总增量，不因某组增长改变预算退出码。未新增公开比较类型，也未修改调用图 JSON、HTML 或函数级比较。

增加内部数值与公开输出测试，覆盖自比、重排、两侧实例数量不同、实例/整组增删、大小写/空白/空名称、标准与 custom 同名、排序、空模块、非最短段头编码，并对合法模块集合逐对核对自比与反向比较性质。公开测试独立解析报告数字，核对分组两侧总量、差值和 whole-file total。本地 native 测试结果为 **240 项通过、0 项失败**。

新增 `scripts/test-size-comparison.sh`，V8 独立验证 17 个完整模块，**23 个进程场景**通过。真实 CLI 精确检查每行 baseline/current/delta、唯一性、排序、分组与文件总量守恒；覆盖 `0B` 自比、预算恰好相等/超过、缩减、总量不变但分组一增一减，并用五秒超时区分进程故障。CI 在保留既有四个脚本后追加新脚本；五个脚本合计 334 个场景。公开 `.mbti` 与修改前完全一致；本次提交的 Linux CI 仍待推送后取得对应记录，前述 `53331c6` 的成功不作为新提交的验证记录。
