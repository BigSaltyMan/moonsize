# moonsize 开发日志

给验收者的一页说明：关键技术决策、AI 在其中的角色、参考来源。每一条都对应仓库里的证据，可以逐条复核。

## 1. 项目周期与入口

仓库建于 2026-10-02，第一个版本 0.1.0 于 10-03 发布，10-05 发布 0.3.0。全部提交位于公开仓库的默认分支 `main`，每个提交只做一件可描述的事。模块入口见 `moon.mod`；`moon check --target native --deny-warn`、`moon test`、`moon build --target wasm` 是本地与 CI 共用的门禁。

## 2. 关键决策

**符号 mangling 规则靠反推，且不猜。** MoonBit 未公开 name 段的命名规则，所以规则来自真实构建产物的实测反推（`moonc` 0.1.20260920，`wasm` 后端），过程与已知边界写在 `README.md` 的 "Symbol names" 一节。解码失败时返回原符号而不是编一个像样的名字 —— 报告里出现假名字比出现原始符号更糟。

**分析模型参考 Twiggy，实现独立。** 体积归因到函数、函数按包聚合、从模块根出发判定可达性，这三个选择来自 Rust 生态的 [Twiggy](https://github.com/rustwasm/twiggy)（MIT/Apache-2.0）。本项目未移植其源码，仅采用同一套分析模型；差异见 `README.md` 与"已知边界"一节。

**调用图保留已知关系并暴露缺口。** `call x` 是精确边；表调用保留静态候选，动态表和引用调用带诊断。额外的边或根会改变可达集合和支配关系，不能据此给实际删减收益统一承诺上界或下界；漏边还可能把实际使用的函数误报为不可达。根、边、诊断和重编译实测需要一起解释。

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

新增 `scripts/test-size-comparison.sh`，V8 独立验证 17 个完整模块，**23 个进程场景**通过。真实 CLI 精确检查每行 baseline/current/delta、唯一性、排序、分组与文件总量守恒；覆盖 `0B` 自比、预算恰好相等/超过、缩减、总量不变但分组一增一减，并用五秒超时区分进程故障。CI 在保留既有四个脚本后追加新脚本；五个脚本合计 334 个场景。公开 `.mbti` 与修改前完全一致。提交 `a66b413` 已取得 [Linux CI 成功记录](https://github.com/BigSaltyMan/moonsize/actions/runs/38733044612)，五个脚本和体积预算任务均成功。

## 10. 预算检查读取本次构建产物（2026-10-15）

此前 `size-budget` job 虽执行 `moon build --target wasm`，预算输入却仍是仓库中的 `examples/fib.wasm`，不能证明本次源码构建结果符合预算。本次将 job 的 `EXAMPLE` 固定为默认 debug 模式的 `_build/wasm/debug/build/examples/examples.wasm`，构建后检查文件存在且非空，并输出路径、字节数和 SHA-256。显式构建 native release CLI，再直接调用实际可执行文件；100KB 正例和 0B 反例都读取同一个构建路径，不回退到发布示例副本。

0B 反例显式捕获退出状态，仅接受 `3` 且含 `over the budget` 原因。返回 `0`、输入错误 `1`、参数错误 `2`、启动失败等其他状态都令步骤失败，不用 `moon run` 的包装状态证明预算拒绝。

PR 工作流继续在同一套已安装工具链下，以默认 debug Wasm 模式构建 baseline 与 current。两侧均先检查实际产物存在且非空，再复制到临时目录，记录来源路径、比较路径、字节数和 SHA-256，最后用本次构建的原生 CLI 比较临时文件。仅在历史基线没有 `examples/moon.pkg` 时保留仓库旧二进制回退，并明确记录它未从基线源码重新构建；存在该包而构建失败时直接终止。

两份 README 的再生成命令补上 `cp _build/wasm/debug/build/examples/examples.wasm examples/fib.wasm`：先构建，再更新发布副本，再从副本生成 HTML，确认新报告后另行更新截图。CI 集成示例同样改读 `$EXAMPLE`。本次没有重新生成仓库示例、HTML 或图片。

本地按工作流提取出的 Bash 命令验证：新示例为 10,675 字节，100KB 返回 `0`，0B 精确返回 `3` 且附预算原因。新产物 SHA-256 为 `b6ae1f1e5dd86f95c82c51eb3f03e65d2070df3bdbf4102881b81a4f812d7a2c`，与仓库副本的 `0e6f10e56434b67adb162cdb56a46553ef38b8de1abd0d0deb1fe56d7173d10c` 不同，证明没有继续分析旧副本。

本地用 `a66b413` 的临时源码快照代替 PR 的 base worktree，原样执行后续构建、非空检查、复制和比较命令；双边构建通过，临时 baseline/current 与各自构建来源逐字节一致，总增量为零。另验证 12 个失败场景，覆盖缺失示例/CLI、错误状态 `0/1/2/126/127`、退出 `3` 但缺少原因，以及基线构建失败直接退出。这里只做临时过程验证，未为 YAML 新增重复的单元测试。

本次未修改公开 API 或预算算法。`moon fmt --check`、`--deny-warn` 检查及 240 项 native 测试通过；五个 CLI 脚本仍覆盖 334 个场景，保留预算等号、增长、缩减和零增长回归。提交 `373c086` 的 [Linux CI 已成功](https://github.com/BigSaltyMan/moonsize/actions/runs/38735545371)，预算日志确认读取本次构建路径及上述 SHA-256，100KB 正例和精确 0B 拒绝均通过。

## 11. 动态 table 的保守诊断（2026-10-15）

在 `373c086` 的 240 项测试、334 个 CLI 场景基线上，先增加公开接口回归，复现「已有静态候选，调用之后还有 `table.set`，图仍被判为完整」。修复前新测试失败，修复后候选和边保留、完整性为 false，`unresolved_count` 仍为零。

新增内部 `table_analysis.mbt`，按导入 table 在前、本地 table 在后的完整索引空间整理导入、导出、声明位置和未建模初始化。导入函数、global 等其他条目不占 table 索引；表解析与 `count_imported_functions` 共用 reference type/limits 读取，后者仍只统计函数导入。typed reference 的 heap type 可以占多字节。显式 `0x40 0x00` 初始化表达式完整消费后才读取下一张表，内容一律标为未知，不通过相邻 `ref.func` 猜测目标。错误编码、截断及不支持的 table64/shared limits 返回明确输入错误，新增 `InvalidTableEncoding(offset, reason)`；不提供完整类型/索引/指令语义验证。

公开 `build(data, bodies, elements)` 迁移为 `build(data)`，只接收完整模块字节，从解析入口取得规范函数体、element 和表上下文，移除可省略写入函数或误传空上下文的路径。`analyze` 保留现有签名，复用相同内部建图逻辑。函数体只解码一次，保留依赖指令和写表来源；先收集所有函数的 `table.set/init/copy/grow/fill`，再处理调用。`table.init` 的目标在第二个操作数，`table.copy` 的目标在第一个；copy 来源和 get/size 不算写入。

新增 `ImportedTableContents`、`ExportedTableContents`、`RuntimeTableMutation`、`UnmodeledTableInitializer`，以及目标缺失于上下文时的 `UnknownTableContents`。静态候选非空也不能抑制任何一种原因。`GraphDiagnostic.source : GraphDiagnosticSource?` 与调用位置分开：运行时来源携带完整函数索引、文件指令偏移、opcode；导入/导出来源指向描述符 kind 字节，初始化来源指向表达式起点，caller/opcode 为空。

每个调用可有多条原因：导入、导出、初始化分别保留，运行时写入按文件偏移去重，不同写入位置分别记录，导出别名合并到首个导出来源。诊断条目数表示原因数量，不能再解释成调用点数量；第 6 节当时的「每处一条」规则由本节扩展。`unresolved_count` 仍只统计没有静态 element 候选的表调用。已知候选边及调用位置不变，诊断使 `graph_complete` 为 false。

文本、JSON、DOT、HTML 共用新原因和来源。JSON 保留 schema version `1`，为带来源的新原因增补 `source: {caller, offset, opcode}`，原有空候选和引用诊断保持原字段形状；新稳定代码及外部枚举匹配迁移写入两份 README。排序为 caller、调用偏移、原因代码、来源偏移。非严格报告保留具体风险；strict 在任何文件写入前以 `3` 拒绝，解析错误仍为 `1`。第一版会保守拒绝实际不执行或不可达函数中的写表行为，不求解运行时 table 数据流。

新增公开 API 与报告回归，实际断言候选、边、完整函数/table 索引、调用偏移与独立写入来源。覆盖五种写表指令、只读与 copy 来源、调用先于写入、间接尾调用、混合导入与 typed global、多个原因/写入来源、空候选加动态风险、可空/非空显式初始化后续表、多字节 heap type，以及截断和不支持的编码。保留 Commit 1 的 39 字节样本及此前解析、比较、预算回归；本地 native 测试为 **259 项通过、0 项失败**。

扩展现有 `scripts/test-graph-diagnostics.sh`，V8 独立验证 28 个完整动态表样本，另保留原有 9 个样本；实际核对 JSON 原因、已知边、调用位置和 writer 来源。图诊断脚本为 **125 个进程场景**，包括普通/尾间接调用 strict、非严格各格式诊断、新文件/已有文件保护及坏编码的输入错误；五个脚本合计 442 个场景。预算正反例仍检查本次构建产物。提交 `0a04980` 的 [Linux CI 已成功](https://github.com/BigSaltyMan/moonsize/actions/runs/38840606670)，259 项测试、五个脚本和体积预算任务均通过。

## 12. 独立 gzip 测量语义与失败展示（2026-10-16）

在 `0a04980` 基线上，先补范围和展示断言：越界段被替换为空输入并压缩成功，错误信息缺少请求范围，文本仍将段独立 gzip / 整文件 gzip 显示为 `SHARE(GZIP)`。三个新增测试在修复前失败，原有 259 项通过；修复后再更新有明确列结构变化的期望，不调整压缩器算法或参数。

`compress_sections` 统一使用 `compressed_span`。先检查 offset、length 非负，offset 不超过文件长度，length 不超过剩余字节，再计算 end，避免加法溢出；错误包含 offset、length、文件长度。合法空范围仍压缩为空流，越界返回该行 `Err`，其他行继续测量。整文件为一个完整 gzip 流；段范围包括 id、长度前缀、payload 和 custom 名称；函数范围使用含长度前缀的 `total_size`。

文本删除压缩占比列，仅显示段 raw、独立 gzip、raw/gzip 比率，并说明独立流不能相加、不能视为整文件 gzip 的份额。整文件百分比保留，小段变大及低于 1 的比率照实展示。局部失败显示 `failed` 并列出段名和具体原因；整文件失败不阻断已成功的局部结果。

HTML 卡片标记 `Whole-file gzip`，段图例改为 `independent gzip`，图表旁说明不可相加及不可作为传输归因。每个函数只测量一次，供函数条目和 treemap 叶子复用；整文件卡片与内嵌数据也共用一个结果。sections、functions 和 treemap 叶子的 `gzip` / `gzipError` 同源配对：成功为数值/null，失败为 null/该项原因。tooltip 不再借用整文件错误，null 不格式化成 0 B；函数条形仍按 body 排名，gzip 比率以完整编码大小为分母；treemap 面积保持 raw 编码字节。HTML 内嵌数据新增 `compression_scope`，与调用图 JSON 无关。公开 `.mbti` 与 `0a04980` 完全一致。

库测试覆盖负数、越界、极大长度、合法空范围、完整与子范围，压缩流解压还原、包含段头/名称、固定重复 custom 样本的非可加性，以及整文件/局部失败的独立展示和实际函数范围错误。保留空输入、重复数据、难压缩数据回归；native 测试为 **269 项通过、0 项失败**。

新增第六个过程脚本 `scripts/test-compression-report.sh`，V8 验证 7 个合法完整模块，**21 个进程场景**覆盖空模块、最小函数、小 custom、多 custom、同名 custom、较大重复段和 39 字节直接尾调用。实际核对文本/HTML 整文件数值、每行范围与比率、HTML 字段配对，并在 Node 中执行页面自身的图表脚本，检查真实 tooltip、treemap 数据传递及渲染边界的局部错误、null 和整文件失败。原五个脚本全部保留，合计 **463 个 CLI 场景**。

两份 README 的例子来自实际测量 `examples/fib.wasm`：raw 10,675 B、整文件 gzip 5,207 B。说明实际服务编码不固定，独立压缩只观察局部可压缩性，优化收益应比较修改前后完整构建产物；不再宣称符号名的网络贡献近乎为零。未再生成示例二进制、HTML 或图片，已有图片和优化计划继续排除在提交外。

`moon info`、格式化、native deny-warn 检查、测试、release 构建、格式检查与 diff 检查通过。预算读取新构建的 10,675 字节示例，100KB 返回 0，0B 精确返回 3 且含预算原因。提交 `7cf1862` 的 [Linux CI 已成功](https://github.com/BigSaltyMan/moonsize/actions/runs/38842804686)，269 项测试、463 个 CLI 场景及预算正反例均通过。

## 13. 函数与包级体积差异（2026-10-16）

在 `7cf1862` 基线上增加 `FunctionStat.raw_name : String?`：非空原始符号在显示名 demangle 前保存，缺失/空名称为 None；真实符号 `(unnamed)` 仍为 Some。`name`、包归因、body/total_size 和偏移口径不变；合成的纯显示测试记录不从显示名猜测 raw_name。

新增公开 `compare_modules(baseline_data, current_data)`，返回 `Result[ModuleSizeDiff, ComparisonError]`，错误区分 Baseline/Current。内部执行现有基础结构检查、import/函数有界读取和名字收集，不构建调用图，也不求解完整 Wasm 类型/指令语义。结果提供文件总量、两侧 code 段/函数编码/开销、函数记录、包记录及分类覆盖数量/字节。

只匹配两侧本地函数中各唯一的同一个非空原始符号。唯一单侧符号标为 added-symbol / removed-symbol；任意一侧重复时，所有相关记录均为 ambiguous，不与普通新增/消失重叠；无名/空名为 missing-symbol。歧义与缺名逐函数逐侧保留，不能用 index、offset、体积、排列或显示名配对。新增/消失只描述二进制符号，可能源于重命名或工具链变化。

包汇总分别聚合两侧全部本地函数，包含无法匹配部分，保持 `(unnamed)` / `(top-level)` 等现有尽力归因。包字节之和等于函数 total_size 之和；函数编码加段头/数量编码等额外开销等于 code 段；函数分类增量完整对账，但不等于整个文件的增量。函数/包记录按增量绝对值降序，再按区分大小写的 UTF-16 字典序身份排列，同一身份最终按状态/定位索引消除平局。当前工具链的 String::compare 使用长度优先顺序，因此新排名单独明确实现字典序，不改变原有段比较排序。

新增 `--diff-functions`，必须配合 baseline，与 HTML/调用图文件输出冲突时在读取输入前返回 2；可组合压缩、retained、dead-code 等文本章节。新 `diff_report.mbt` 输出函数、包、匹配覆盖和 code 开销四节，raw 符号引用并转义；`--top` 分别限制两种排名，top=0 保留所有汇总和覆盖情况。未启用时 baseline 仍保持原来的文件/段比较。CLI 每个文件只读一次，baseline 同时保留 bytes/parsed；所有可能失败的比较准备在正常报告前完成。当前 strict 仍可返回 3，解析/收集错误为 1，预算仍只约束整个文件增长。

新增公开 API 黑盒回归，覆盖自比、索引重排、前置导入、增长/缩减、新增/消失、单侧/双侧重名及另一侧缺失、显示名碰撞、空/缺名/字面 `(unnamed)`、长度前缀 127→128、函数数量编码 127→128、空/显式空 code、两侧解析和统计错误、无需完整 baseline 图，以及文本转义/隐藏排名。逐条检查函数分类不遗漏不重复、包/函数总量和 code 开销三类对账。另先复现非法 UTF-8 名称字节 FF / FE 被有损解码成同一字符而误匹配，再将 `read_function_names` 改为严格解码：可选调试名称的受损后缀留为无名，前面已读名称保留；合法 U+FFFD / BOM 不受影响。解析函数签名不变，避免凭损失信息的字符串建立身份。native 测试为 **284 项通过、0 项失败**。

第七个脚本 `scripts/test-function-diff.sh` 通过 **35 个进程场景**，V8 验证 32 份完整模块。按手工指定的符号配对账本断言实际每行身份、两侧索引和大小、状态、增量、排名、分类覆盖、包总量、code 开销。包括 top=0/1、unicode、参数冲突的新建/既有文件保护、坏 baseline 的准备失败无半份报告、缺名产物的预算等号/超限、非 code 增长仍触发预算，以及 strict 当前/基线区别。保留前六个脚本，合计 **498 个 CLI 场景**。

源码演示位于 `examples/function-diff/{before,after}.mbt`；两者是脚本输入，没有另设包影响现有示例预算。`scripts/demo-function-diff.sh` 在同一个独立临时项目里按 before→after→rollback 构建，统一 `--target wasm --debug --no-strip`，V8 确认合法且存在 name 段，再执行两次真实 CLI 比较。自动检查 classify 增长、新 weighted_score 符号、包增长，以及回退后完整 Wasm 字节一致、全部符号匹配且差异为零。产物和报告保留在忽略的 `_build/function-diff-demo.*`，命令写入两份 README，并接入 Linux CI。

MoonBit `0.10.13+cbb11c36f` 的实际演示：文件 4,977→10,785 B（+5,808）；classify 29→55 B（+26），weighted_score 新符号 103 B，demo::functiondiff 包 29→158 B（+129）。原有 29 个符号仍匹配，current 另有 18 个唯一新增符号（包含运行时辅助函数）共 2,055 B；已匹配增量 +70 B，函数编码总增量 +2,125 B，code 开销两侧均为 4 B。回退文件和函数差异均为零，不把手写数字作为测试依据。

公开 `.mbti` 增量限定为 raw_name、Options.diff_functions，以及比较状态/错误/结果类型、compare_modules 和文本渲染入口。原有解析、建图、压缩、预算 API 不变。检查、七个脚本、真实源码演示及预算正反例完成后提交；取得目标提交的 Linux CI 成功记录后，再标记远程验证完成。图片和优化计划继续保留在工作区。

## 14. 初审反馈后的收益边界与重编译案例

初审反馈指出保守引用图和逐段压缩不足以支撑精确删减收益承诺。原申报及 README 的“删掉谁能省多少”“实际能释放”表述已撤回。retained 定义为固定图/根集合中的支配子树函数编码权重；它不模拟调用者改写、重新编译、数据和名称删减，也不是整文件 gzip 减量。所有 element 引用保守作为根的策略单独说明；无诊断和 strict 通过也不证明该集合等于真实执行，或能预测重编译收益。

两份 README、CLI 帮助、retained 表格、公共类型注释、导出模型说明和 HTML 同步修订；retained 表格即使图完整或 top=0 也保留边界。HTML 始终显示模型与真实收益的区别，示例 HTML 已重新生成，已有图片未修改。新增两个测试固定无诊断情况下的文本/HTML 说明，不改变图算法、数值字段或公开接口。

`scripts/demo-retained-boundaries.mjs` 在忽略目录内建立同路径工程，对独占分支和共享依赖各执行 debug/release 的 before→after→rollback，统一 `--target wasm --no-strip`，V8 验证模块，moonrun 执行并核对基础输出和回退字节。`#inline(never)` 保留调查对象，after 有意移除可选输出，不声称业务语义完全不变。Windows 本机独占 debug 为 retained 52 B、Wasm 减少 656 B、整文件 gzip 减少 237 B；共享 debug 为 16 B、127 B、41 B。release 的 gzip 减量分别为 228 B、39 B。各段独立 gzip 的减少量也不等于整流减少量。

另有明确标为手工 Wasm 的私有表对照：run() 始终返回 42，element 保守根使目标不被报告为死代码，retained 5 B、文件减少 38 B、gzip 减少 27 B；不冒充 MoonBit 重编译案例。运行时写表对照合法且可执行，仍产生两条分析缺口并由 strict 返回 3，不提供删除收益结论。

边界、案例和原始测量快照见 `docs/retained-size-boundaries.md` 与 `docs/retained-boundaries-results.json`；项目说明与复审文字分别在 `docs/october-proposal.md`、`docs/october-review-response.md`。CI 运行案例并上传 `retained-boundary-evidence`，包含 JSON、Wasm、原始分析/比较报告及运行输出，使用性质断言而非强制跨平台字节数相等。本地 286 项测试、七个脚本 498 个进程场景、函数差异源码演示及边界案例通过；目标提交的 Linux 结果以其运行记录为准。

## 15. 优化实验报告（2026-10-16，本地未提交）

为“调查候选—修改源码—重建—验证实际变化”增加通用输出模式。`--experiment report.html|report.json` 必须配合 baseline；`--experiment-context context.json` 可附上实验假设、两侧源码标识、构建命令、工具链、target、mode、strip、features 和业务验证状态。说明中的命令不会被执行，所有构建与验证信息均标为调用者声明。缺失上下文显示 not-recorded；条件不同逐字段提示；validation failed/not-run 原样保留，文件变小也不会自动成为业务正确的优化。

核心实现 `experiment.mbt` 使用已有比较、分析和整文件压缩 API，SHA-256 使用已依赖的 `moonbitlang/x/crypto`，不引入新模块依赖。报告记录两侧实际字节哈希、文件和整文件 gzip 差值、图完整性及诊断、完整段差异、按原始符号匹配的函数变化、尽力包归因、匹配覆盖率和 code 开销。数值统一 current − baseline；top 只限制函数/包明细，不裁掉汇总。gzip 失败保留 null 和原因。HTML 无脚本或外部资源，路径、名称和声明均转义。

新增公开函数 `check_experiment_context`、`experiment_report`、`render_experiment_html`，Options 增加 experiment/experiment_context 两个可读字段。通过 `moon info` 核对现有函数签名与类型字段未被删除。CLI 对说明先做参数/结构检查；两侧完成分析后才写报告。strict 检查前后两侧，任一不完整返回 3 且不创建文件。预算继续只约束原始文件增长，拒绝时保留报告及预算状态并返回 3；业务验证声明不改变测量命令的退出码。已存在的输出路径一律返回 1，防止覆盖报告或通过路径别名覆盖输入。

新增 7 项库/参数测试，native 合计 **293/293**。新增 `scripts/test-optimization-experiment.mjs` 的 **41 个真实 CLI 场景**，覆盖增长、缩减、自比、独立 SHA-256 核对、整文件 gzip 对账、未匹配覆盖和 code 开销、错误配置/JSON、两侧输入错误、两侧 strict、HTML 转义、预算报告、新建失败和已有路径保护。原七个脚本 **498 个场景**和函数差异源码演示全部通过，合计 **539 个 CLI 场景**。

边界案例脚本为四组真实 MoonBit 源码重编译和一组人工 Wasm 对照生成实验说明、HTML、JSON，核对新报告与原始测量的哈希和差值一致。`unique-debug` 示例为文件 10824→10168 B、整文件 gzip 5236→4999 B；通过源码回退、原始输出与基础行为检查，明确有意移除可选输出。示例保存到 `examples/optimization-experiment.html/json`，用法和库接口见 `docs/optimization-experiments.md`，两份 README 和复审材料已同步。

本次完成本地格式、deny-warn、native 测试/release 构建及原有回归检查。CI 配置已加入新回归并上传实验报告；按用户要求不提交、不推送，因此本次没有远端 Linux CI 结果。浏览器工具拒绝 file 协议，未进行浏览器视觉验收；已检查 HTML 结构、转义、测量与离线资源约束。原有图片和优化计划保留。
