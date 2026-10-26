# moonsize 开发日志

给验收者的一页说明：关键技术决策、AI 在其中的角色、参考来源。每一条都对应仓库里的证据，可以逐条复核。

当前交付入口：[复审证据](review-evidence.md)、[0.4.0迁移](migration-0.4.md)、
[发布与目标CI记录](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.4.0)。
早期章节中的版本、测试数量和待验收状态保留为历史；当前状态见第20节及发布记录。

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

## 16. 函数引入路径与根来源（2026-10-16，本地实现）

新增公开 `explain_function(data, target_index, root?, limits?)`，从完整字节检查模块、收集含导入的函数身份并构建规范调用图，不为查询计算支配树。结果区分 PathFound、PathNotFound、PathSearchLimited，携带目标、选中根、完整或受限前缀的根来源、有序节点/边、全图诊断及计数。导入函数 encoded_size 为 None/JSON null；非法目标、非模型根、幽灵根/边、坏输入和无效限额返回具体错误。

根来源独立整理为每个 export 名称及序号、start、每段 element 引用，保留同一函数的多个来源。位置明确为段起点及条目/段序号，不伪装为指令偏移。与真实 analyze.roots 对照，默认仍将所有 element 函数保守作为根；目标自身是根时如实给出零步路径。指定真实模型根后可以查看上游间接候选或引用边，不改变全局根、可达性和 retained。

确定性 BFS 使用带位置的 graph.edges，根按 index，邻接按目标 index、Direct/Reference/Indirect、指令偏移排序。按 offset 缓存操作码解码，保留 call/return_call/ref.func/call_indirect/return_call_indirect 和 table/type；不猜测引用调用目标。默认限额为 100,000 节点、1,000,000 边、256 层；分别限制根/访问节点、根来源/索引边/检查边。准备阶段也可返回受限，截断不冒充未找到，循环不造成无穷搜索。查询限额不限制已有模块解析、建图和排序成本。

新增 `--why-index`、`--why-root`、`--why-json`，索引解析覆盖非负 Int 范围，不沿用 top 的一百万上限。查询仅可组合 strict，其他模式和显式 top 在读文件前报错。完成查询返回 0，输入/索引/根/写入错误为 1，参数错误为 2，受限或 strict 拒绝为 3。JSON 拒绝已有输出路径，strict 在输出前检查全图，即使已找到路径也不绕过缺口。文本解释查询范围、根、边证据和限制；独立 JSON 格式版本 1 保留结构化数据。所有结果明确属于引用模型，不是执行轨迹或删除、重编译、gzip 收益预测。

新增 17 项公开接口回归，当前 native 合计 **310/310**。覆盖直接/尾调用、菱形、多根、循环和平局、根别名/start/保守 element、指定根的间接/引用路径、导入/null、无名/重名/转义、错误索引、限额的恰好完成及截断、引用调用缺口和动态表写入来源。`scripts/test-function-path.mjs` 独立用 V8 验证 17 个完整模块，运行 **67 个真实进程场景**，逐条核对 JSON、指令字节/偏移、来源、状态、计数、全部模式冲突、严格拒绝和已有文件/硬链接别名保护。八个原有回归的 539 场景继续通过，合计 **606 个 CLI 场景**。

`scripts/demo-function-path.mjs` 在 `_build/function-path-demo/` 的同路径独立项目中执行 before→after→rollback，统一 wasm/debug/no-strip，保存源码、toolchain、构建/查询日志、运行输出、Wasm/CLI 哈希、路径及实验 HTML/JSON。从真实符号定位 path_target，动态发现可达的导出根，经过 path_upstream 得到两边路径，不写死编译器 index。删除上游可选输出后重建，基础输出保持；不声称完整行为等价。当前工具链实际测得文件 10497→10235 B（−262 B）、整文件 gzip 减少 101 B，测试只对账真实测量，不固定跨平台数值。回退后完整 Wasm 字节、行为和路径 JSON 恢复。

两份 README、帮助和 CI 已加入查询、接口迁移、限额和演示说明，CI 保留既有回归并上传 function-path-evidence。moon info 的接口差异仅为查询类型、四个查询/描述/渲染入口及 Options 三个字段；旧 parse/analyze/build 等签名不变。格式、deny-warn、测试、release 构建和 diff 检查通过，三个源码演示继续成功；预算读取新构建的 10675 B 示例，100KB 返回 0，0B 精确返回 3。

本地 HEAD 仍为 e5833fe，收益边界、优化实验及 HTML 前置工作尚有未提交改动。本功能保留为独立可审阅改动，未将前置功能、图片或规划混入提交；按既定约束不推送，Linux CI 尚未运行，不能将本地成功标为远程验证完成。

## 17. 多指标体积预算与 CI 摘要（2026-10-16）

本次用户授权整理前置依赖、提交、正常推送并核验目标 SHA 的 Linux CI。先将模型边界和可复现优化实验整理为 `51ace59`，用暂存区导出的独立工程确认 293 项测试和 native 构建；再将函数路径查询独立提交为 `0fd5153`，确认 310 项测试。此前小节中的“未提交/不推送”为当时状态，本次授权覆盖后续交付；未把尚未实施的 HTML 改版规划当成已完成，也未纳入已有图片或规划文档。

新增 `budget.mbt` 的 compile_budget(Json)、compile_budget_text(String)、budget_requires_baseline 和 evaluate_budget。CompiledBudget 在外部接口中为 opaque type，私有规则数组不能被外部修改；修改原始配置对象也不改变已编译规则。配置检查版本、非空规则、唯一 id、显式 metric/mode、非负 Int 阈值、package 要求与未知字段，按规则位置/字段列出问题。文本入口额外检查整数原始 token，防止极小小数被通用 JSON Double 转换舍入后误通过；配置和 growth 缺 baseline 在 Wasm I/O 前返回 2。

支持 file.raw、整文件单流 file.gzip、完整 code.raw，以及按现有符号标签累计本地函数 total_size 的 package.raw。absolute 检查 current，growth 检查 current − baseline，等号通过，缩小保留负数，空模块的 code 是真实零。每次预算求值每侧所需指标只测一次，多条包规则共用统计/聚合，不建图或计算支配树；absolute 不请求无关 baseline 归因。CLI 每个输入文件只读一次，常规分析不按规则重复；已有 whole gzip 测量供 compress 文本复用。

缺名、受损名称和未识别的 MoonBit mangling 导致未归因函数时，包预算保守返回 unavailable，保留覆盖数量/字节与观察到的标签存在性。充分归因的 growth 比较允许标签单侧缺失记零，并解释新出现/消失；两侧均无标签不能零值放行。文件、code、gzip 的成功测量不被归因失败抹掉，压缩失败保持 null 和实际错误，不回退为 raw/零。包指标不是完整源码成本或删除收益，gzip 不模拟服务端网络编码。

新增 --budget、--budget-json、--budget-md；与 max-size、路径查询、实验、HTML 和调用图模式冲突时先返回 2。适用的普通文本选项保持可用，原 max-size 行为不变。准备完成后输出，strict 仍先以 3 拒绝不完整图，不创建或覆盖报告。所有目标路径在第一次写入前一起检查，拒绝已有文件、目录、输入/证据别名；后续 I/O 失败返回 1，不声称所有输出成功。部分已成功写入的证据允许保留。

budget_report.mbt 提供逐规则英文文本、独立版本 1 JSON 和 Markdown；都保留 id、指标/包、mode、current/baseline/delta、limit、passed/exceeded/unavailable 和原因。JSON 还记录实际产物 SHA-256、输入路径、覆盖信息、压缩口径、整体状态及退出码；Markdown 对竖线、换行、反引号与 HTML/Markdown 字符转义。全部通过为 0，可评估且超限为 3，输入/测量/归因/写入错误为 1，配置/参数为 2；unavailable 优先于 exceeded，所有失败原因分别保留。不发 PR 评论或外部通知。

新增 20 项库/参数/渲染回归，native 合计 **330/330**；包括四指标 absolute/growth、等号/正负增量、函数长度 LEB 边界、真实零和未知区别、包新出现/消失/缺失、归因覆盖不足、所需侧区分、导入索引空间、配置私有快照、数值类型和舍入、两侧输入错误、Markdown 转义。白盒仅在已有测量结果边界注入压缩 Err，确认 unavailable/退出 1/null/错误一致，无生产故障开关。

新增 scripts/test-budget.mjs，V8 独立确认 6 个完整模块，**113 个实际进程场景**涵盖所有指标、重复规则、JSON/SHA 对账、混合失败优先级、配置先于业务输入、模式冲突、新建/已有目标/硬链接/目录/部分写入失败、strict 新建与已有输出、坏 current/baseline 不产生正常报告，以及旧 max-size 的精确正反例。既有九个回归脚本的 606 场景继续通过，合计 **719 个 CLI 场景**。

scripts/demo-budget.mjs 在 `_build/budget-demo/` 同路径工程内以 wasm/debug/no-strip 构建 before→after→rollback，记录源码、命令、toolchain、实际哈希、运行输出和 JSON/Markdown。新增可选输出后，当前工具链实测 file.raw +423 B、whole gzip +149 B、code.raw +44 B、demo::budgetdemo +29 B；限额来自实际测量，不固定跨平台 gzip 字节。通过反例精确为 0/3，另验证坏输入为 1；回退恢复完整字节、原输出和规则结果。基础输出保持、可选输出有意增加，不声称行为完全等价。原有三个源码演示全部通过。

两份 README、帮助、docs/budgets.md 和两个实际配置同步更新。examples/budget.json 用于真实演示包；examples/ci-budget.json 对本次新构建示例设置 file/gzip/code 绝对预算。CI 保留全部原有任务，新增预算回归与源码演示、上传预算证据，并将新示例的实际 Markdown 写入 GITHUB_STEP_SUMMARY。原生检查、测试、release、格式和 diff 检查通过；新构建 10675 B 示例的旧 100KB/0B 预算分别为 0/3，多指标配置通过。接口增量限定为预算 opaque/结果/错误类型、入口/渲染和 Options 三字段，原有公开函数签名不变。远端验证以本次最终 SHA 对应的实际 Actions 运行记录为准。

## 18. 原 HTML 报告的信息层级与可读性（2026-10-16）

改版范围为原 --html 报告，未改实验报告、CLI 参数或分析算法。新增 html_assets.mbt 集中维护可读的 CSS/JS；顶部提供完整路径、章节导航、四张精确字节卡和始终可见的模型边界。实际图诊断置于折叠区之外，无诊断也不宣称完整验证或安全删除。布局使用系统字体、暖白背景、深色正文和青色重点；四/二/一卡片、双/单列图表、局部表格滚动、键盘焦点及打印样式分别处理。

段/函数柱图按各自条目数确定高度，标签适应容器，raw 与独立 gzip 使用固定的同一数值轴；压缩失败保留该项原因，压缩变大不隐藏。模块环图明确以已归因函数编码之和为分母，code 完整段占比在提示中另外计算。环图和 raw encoded treemap 使用模块身份确定颜色，文本和轮廓补充模型不可达状态。新增原生可折叠 Top 20 函数表，直接消费同一份已排序 JSON 和已有 gzip Result，显示 full-space index、完整名称/模块、body/encoded/gzip 与模型状态，不重复分析或压缩。图表库缺失或初始化失败保留静态卡片、表格和方法说明。

公开 render_html 签名和 schema_version=1 不变，旧 payload 字段和值逐项对账一致；仅 treemap 函数叶子增加 index。示例输入继续使用未替换的 examples/fib.wasm，SHA-256 为 0e6f10e56434b67adb162cdb56a46553ef38b8de1abd0d0deb1fe56d7173d10c，file/code/whole gzip 分别为 10675/5166/5207 B，模型不可达编码 0 B、47 个本地函数。已有 report.png 未覆盖，新截图分别保存为 report-desktop.jpg 和 report-mobile.jpg。

新增 6 项库测试，native 共 **336/336**。新 scripts/test-html-report.mjs 用 6 个 V8 验证的模块及长路径/CDN 场景运行 **8 个真实进程场景**，与原有 719 个合计 **727 个 CLI 场景**；对实际输出逐行核对排序、索引、原始范围、数值与错误，并执行生成脚本的可观察图表/DOM 适配器，验证轴、分母、颜色、空/失败、切换、resize 和打印状态。这些适配器不冒充浏览器布局。原十个脚本、四个源码演示与回退检查、预算 100KB/0B 正反例继续通过。CI 追加新回归，保留既有任务。

按用户指定，通过 npm run dev 的 HTTP 页面 http://localhost:5173 做真实 Chromium 验收，复用已运行的 5173 服务器。1440/1024/768/390 宽度均无页面横向溢出，图表绘制和 gzip 切换正常；验证实际 tooltip、手机局部表格滚动、Enter 展开/收起、454 字符 Unicode 名称与重名索引、移除图表库后的静态回退和真实缺口警告。两张 JPEG 来自真实视口。初始 file 协议被浏览器拒绝后未绕过，用户指定 HTTP 后在该地址验收。实际断网下打开迁移文件、打印/PDF 输出未完成，现有浏览器 API 没有网络切断、打印或 PDF 导出能力；资源自包含及打印事件回归不能替代这两项实测。详细边界见 docs/html-report.md。远端 Linux 结果以推送后目标 SHA 的实际 CI 记录为准。

README 截图后续更新：两份 README 均直接展示 report-desktop.jpg 与 report-mobile.jpg，并将再生成说明同步为实际视口尺寸和 localhost:5173 地址；旧 report.png 保留在工作区，未覆盖或提交。仅修改文档，核对两张 JPEG 的实际尺寸、引用路径及 diff，无需重复运行分析实现测试。

## 19. 自包含 HTML 发行与实际离线/PDF 验收（2026-10-16）

基线为 main 9ae56c2。确认旧 CLI 从 cwd、父目录 assets 读取 ECharts，缺失时输出 CDN 页面，违背默认离线交付承诺。本次移除文件搜索，以固定 SHA-256 的 ECharts 5.6.0 生成私有 cmd/main/echarts_generated.mbt。当前 MoonBit 工具链已实际验证普通 String literal/StringBuilder 的 native 编译；不依赖未经确认的资源指令。生成器将源码分为有界行并原样重组，避免编译器长行警告，--check 对比格式化后的完整生成物及资源哈希。Node 只在更新资源/测试时使用；常规 MoonBit 构建直接使用已提交生成物，生产 CLI 无下载、浏览器或 Node 依赖。补齐上游完整 Apache LICENSE/NOTICE 与 bundled d3 许可、固定来源、哈希和更新步骤。

公开 render_html 签名不变，库调用者未传 echarts 时仍选择兼容 CDN 模式；CLI 始终明确传入编译资源。独立 cwd 生成、cwd/父目录放置同名恶意资源的输出逐字一致，实际报告中的库源码重构后 SHA-256 与 vendored 文件相同。Windows native release 从 804864 增至 2893824 B（+2088960 B）；原 Wasm 示例预算口径未改。使用同一 examples/fib.wasm（0e6f10e56434b67adb162cdb56a46553ef38b8de1abd0d0deb1fe56d7173d10c）经实际 CLI 重生成页面，所有旧 DATA 字段和值完整相等，文件/code/whole gzip/不可达编码仍为 10675/5166/5207/0 B。屏幕布局未改，既有两张截图和用户 report.png 不覆盖。

实际打印发现旧实现按屏幕 canvas 宽度输出，右端会裁切，且悬浮提示进入 PDF。本次 beforeprint 先建立 A4 的 186mm 内容宽度和单列图表，再以无动画 resize、同步 ZRender flush 完成绘制；隐藏 hover 提示，打印使用紧凑图高和完整原生模块图例。概览、构成、函数、模块地图按章节分页，表格跨页重复表头，必要方法自动展开；打印后原内联样式、宽高、展开状态及环图标签恢复。小环图不打印易裁切的内部百分比，完整图例保留每片精确字节。

新增 scripts/test-html-portability.mjs：3 个实际 CLI 场景，V8 验证长名称/缺口样本，固定源输入与库哈希，复制件目录含空格和中文且只有 HTML。关闭原 context 后，新 context 从创建时即 offline、禁用 service worker，仅将复制件字节映射为主 HTTP 文档，其他资源请求不提供替代；四张图实际绘制，tooltip、数字和表格可用，外部请求及阻断错误为零，fetch 控制确实失败。此方式遵守 AGENTS 禁止 file:// 的规则，没有声称实测 OS 双击打开或借用原页缓存。

测试环境固定 Playwright 1.58.2、PDF.js 5.4.624；本机 Edge 156.0.4314.23、Windows 10.0.26300、Poppler 26.07.0。真实 A4 浏览器 PDF 分别 5 页与 4 页，Poppler 独立渲染，每页检查数据/完整名称、图表、表格列和模型说明；已逐页人工检查全部 9 张 PNG，无裁切、覆盖、空黑图或意外空白页。PDF.js 同时检查文本与图形，真实打印事件校验纸宽及状态恢复，再在 1440/1024/768/390 下检查布局。原 336 项测试、727 CLI 场景、四个源码演示及预算 0/3 继续通过，加上迁移 3 场景共 730。资源与打印最终修正后重新运行对应检查和浏览器验收。

详细复现见 docs/html-delivery.md，本地哈希/环境快照见 docs/html-delivery-results.json；PDF、页面 PNG 和逐页 manual-review.md 保存在 _build/html-delivery-verification/latest.json 指向的 run-JM2Zrx 目录。CI 新增锁定开发依赖、Chromium 实际离线/PDF 测试和 html-delivery-evidence；不会将适配器检查或 CI 自动检查冒充人工视觉验收。非 Chromium 浏览器、物理打印机和 file:// 双击路径未实测，A4/12mm 设置范围单独说明。目标远程状态以最终提交 SHA 的 CI 为准。

Linux CI 首次执行已通过资源校验、336 项测试、全部旧回归和预算；新增 PDF 检查因提取文本的字形分段差异失败。下载实际 Linux PDF 并检查页面，Whole-file gzip 标签和 5207 B 卡片均正确；PDF.js 返回 Whole-、fi、le gzip 三段，测试自行 join 空格造成误判。后续修正仅在 PDF 文本比较时去除提取空白，保留全部文字、标点、数字及单位，增加连字分段正例和错字/错数反例；不跳过 PDF 内容断言，也不修改生产页面或测量。修正后重新运行实际浏览器/PDF 回归并正常推送，由新目标 SHA 的 CI 确认。

## 20. 复审证据与 0.4.0 发布收口（2026-10-16）

当前入口为 [复审证据索引](review-evidence.md)、[最终项目说明](october-proposal.md)与[逐项回复](october-review-response.md)。章节1—19保留当时的实现/测试状态，不能以其中旧版本、旧数量或待验收状态代替当前交付。分析实现基线3a07e03，本次不改算法；没有承诺完整Wasm语义、任意规模性能、精确删减或实际网络成本。

实际下载Mooncakes最新0.3.0包并核对注册表SHA-256（60339bdfebc95cfe30948ea1ba5b5dda75e032c0b61c1956e2512d3a4719246c），确认旧包仍为三参数build、无统一图诊断/路径/实验/多预算。新版本选为0.4.0，迁移说明逐项列出七处签名变化、新错误和可读字段，分别解释报告JSON版本、模式约束、退出码与CLI/库资源区别。moon add仅安装库依赖，独立CLI需源码构建。

公开证据保留未经改写的测量JSON，补路径、预算结果与两份实际PDF。PDF从既有run-JM2Zrx按原文件名复制，5+4页，摘要与既有验收记录一致；人工逐页记录一同公开。这是历史Windows人工验收，本轮重新执行的实际离线/PDF测试及未来Linux自动检查不会改称人工验收。已验证HTTP主文档映射的全新断网上下文、零外部请求、图表/数据和打印恢复；file://、非Chromium及实体打印机仍未验证。

本轮本地实际运行336项native测试（0失败）、730个CLI场景、四个源码演示及预算0/3，资源生成校验与格式检查通过。独占/共享debug案例仍为R=52/16、重建减量656/127、whole gzip减量237/41 B。案例有意移除可选输出，仅验证保留的基础行为及字节级回退。路径/预算新快照记录当次工具链和输入哈希，不将路径字节相加解释为收益。

新增scripts/verify-release-consumer.mjs，在仓库外新建项目、从注册表安装精确版本，编译并执行parse/stat/build、真实尾调用路径、差异、实验和预算0/3。发布采用明确提交的外部干净导出，检查实际ZIP清单及许可，排除临时产物和无关图片/规划；不得从混有用户文件的工作区直接发布。

提交产生后的确切SHA、该SHA Linux CI、包校验和、干净导出和精确公开版本消费结果写入[0.4.0发布记录](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.4.0)，避免循环amend记录自身SHA。以上本地检查不代替后续注册表消费或目标远程CI，发布记录才是对应结果入口。用户原report.png及其他本地规划文件不纳入提交，没有复制个人联系方式或代交表单。

首次仓库外git archive被Windows的core.autocrlf转换了vendored JS换行，干净资源哈希校验明确失败；尚未发布。后续在.gitattributes为固定资源和有字节摘要的复审附件设置-text，保留原始blob字节，再从新提交完整导出验证。没有修改第三方资源、更新期望哈希或绕过失败；实际包与消费结果以最终发布记录为准。

## 21. 统一报告输出保护（2026-10-20）

基线为main 5f1452a。核对六类目标：HTML、调用图DOT/JSON、实验HTML/JSON、路径JSON、预算JSON/Markdown。旧HTML/图直接用x/fs截断写；新模式仅先检查存在，也没有独占创建。用旧CLI对隔离39字节样本执行新增回归，实际复现输入被HTML覆盖，输入SHA-256改变；没有使用仓库原始Wasm做覆盖实验。

cmd/main/output.mbt集中预检与写入，全部目标在第一次写入前一起检查。输入/说明/配置与解析分析、strict拒绝先执行；实验目标检查也统一到strict之后，遇到图缺口时即使目标已存在仍返回3。正常新路径继续写报告，预算超限可保存证据并返回3，输出保护或后续写入错误返回1且不打印成功提示。没有改变分析、JSON格式或预算阈值，生成的公共库.mbti与此前接口一致。

当前x/fs没有公开独占创建API，新增CLI私有output_native.c，Windows用CreateFileW(CREATE_NEW)，Linux用open(O_CREAT|O_EXCL|O_WRONLY)。使用操作系统路径查找与独占创建，拒绝现有文件、目录及相对/绝对/硬链接/符号链接别名；POSIX用lstat识别悬空链接。Windows使用UTF-8到UTF-16转换，拒绝ADS与设备命名空间，正常中文及空格路径通过。处理短写、EINTR及关闭错误，不引入生产Node依赖，不删除或替换目标。独占创建防止预检后出现的同名文件被截断，但不是多文件事务、崩溃原子写入或断电持久性保证；后续失败可能留下前面的新文件或自己的部分文件，不防御恶意替换父目录/挂载点等行为。

新增scripts/test-output-protection.mjs，在独立OS临时目录构造并由V8确认合法模块。每个拒绝检查精确退出码、英文原因、输入/baseline/配置/说明/已有证据SHA-256不变及没有正常成功输出；覆盖八种报告表示、已有目标、路径别名、硬链接、权限拒绝、strict先后顺序、多预算目标预检、后续部分失败和12个竞争CLI进程恰好一个成功。Windows本机158个进程场景通过，8组符号链接能力限制EPERM明确打印，不计作通过；Linux CI要求实际执行符号链接分支，结果以本提交推送后的目标运行记录为准。

原336项native测试、730个CLI场景、四个源码演示和预算0/3全部通过，本机合计888个CLI场景。实际HTTP根页面先打开，再跑原迁移/断网/A4 PDF回归，图表、数据和打印状态恢复通过。新生成记录位于本地_build/html-delivery-verification的独立运行目录，不将自动检查称为新增人工逐页检查；页面和原截图未改。

旧图诊断测试曾在严格拒绝后覆盖哨兵文件来测试普通报告，改为新目标且继续确认哨兵不变；retained演示的图先写独立新目录，校验后由演示脚本明确复制为自己的稳定证据文件。两份README与帮助同步默认拒绝覆盖策略；示例先生成新暂存输入/HTML，核对哈希和数值后由用户明确替换，暂存目录不进入Git或发布包。文档说明当前源代码更新尚未发布到旧0.4.0包，不虚构新版本。详情见[输出保护范围](output-protection.md)。原report.png、AGENTS及各规划文件继续保留在工作区，不纳入本提交。

## 22. 可复现大模块分析基准（2026-10-20）

基线0cadc6b，本次只增加Node内置模块脚本、原CI中的一次小档smoke与说明，不修改分析算法、公开API、CLI参数或退出码，也不实现数据段明细。脚本支持smoke、默认和手动large，独立新运行目录保存输入、原始日志、results.json和summary.md；默认一次预热、三次正式，只有10k档追加retained报告对照。以单调时钟记录完整CLI进程至关闭，生成与验证分开计时，不测内部阶段或峰值内存。

合成输入为稀疏二叉直接调用树和受控重复间接调用，参数确定性生成并再次核对SHA-256，经V8独立验证。受限编码检查器复核数量，区分预计逐调用点来源边记录与去重后的fixture邻接数；默认间接样本256调用点×128候选对应32768条预计来源记录、128个fixture邻接关系，不冒充实际CLI图导出计数。真实fib仅是47本地/1导入函数的小型对照，调用/候选/边数未测量，不能宣称真实大型项目覆盖。

每次分析有可配置超时，只终止自己的子进程；验证、启动、非预期退出、超时分别记录，失败组不生成统计，已完成记录保留，脚本非零退出。两个受控小检查验证超时后子进程已终止及启动失败分类，未铺开错误矩阵。smoke严格只有两个样本各一次真实CLI调用。

本地仅执行语法检查、一次native release构建、一次定向smoke和一次默认基准；没有moon info/fmt、全量native/CLI、HTML/PDF或四个源码演示重跑。默认原始记录run-4kyAei：1k普通报告中位30.9541ms，10k普通67.8865ms、retained83.2089ms，受控重复间接调用37.7880ms，fib33.2310ms，全部成功；正式原始记录重算统计一致。两种报告都已计算retained，差值不能解释成支配树耗时。当前形态没有明显瓶颈，暂不为后续优化制造结论。未执行50k档，峰值内存和真实大型项目未覆盖。

详细输入哈希、环境、完整原始时间与复现命令见[性能基准](performance.md)。CI仅复用现有Node24/native构建追加一次smoke并上传小型证据，无毫秒门槛，默认与large不进入常规CI；既有完整检查保留，最终远程结果以本次提交SHA的CI为准。原图片、AGENTS及规划文件继续排除，不发布Mooncakes。

## 23. Wasm 数据段编码明细（2026-10-20）

基线c1c233d。没有安排性能重构；新增inspect_data_segments，内部执行parse_module，复用有界Reader、受检查的u32转换和指令解码器。支持data模式0/1/2，datacount如存在须匹配实际数量，两段payload均完整消费。只保存条目和payload范围、实际字段宽度及表达式范围，不复制全部payload；表达式包括end，明确not_evaluated/passive not_applicable，不输出内存偏移。

新增文本与独立schema_version 1 JSON；文本按payload降序、原始序号升序，Top不改变全部汇总和原序JSON。默认报告与analyze签名不变，不增加Analysis、WasmModule、Sections字段。Options新增两个开关，WasmError新增InvalidDataEncoding（位置、原因），外部穷举匹配须迁移。全部可失败解析在正常输出前完成，strict拒绝仍早于统一目标预检与独占写入；错误1、冲突2、strict/max-size的3保持原契约。

本地35项定向测试通过（新增数据段5项及受影响CLI文件），覆盖账本、三种模式、空值区别、多字节与合法非最短编码、立即数0x0b、截断/未知指令/非法模式/尾随字节/datacount不匹配，以及参数冲突。一次native release构建后，轻量脚本5个真实CLI场景通过，V8独立验证38字节混合模块；22 B data = 6 B payload + 13 B条目元数据 + 3 B段级开销。文本Top1、完整JSON、baseline/max-size/strict可组合，坏输入无报告，已有JSON拒绝且原字节不变。证据在_build/data-segments-verification/run-KOKUko，详见[数据段说明](data-segments.md)。

生成接口经审查，增量仅数据段元数据/渲染入口、Options和错误分支（新类型派生Eq/Debug）；没有无关接口调整。受限进程首次格式化/测试遇到旧_build缓存权限，提升执行权限后定向检查通过，没有把权限失败计作测试成功。完整回归、原有源码演示及预算由目标SHA Linux CI执行；本地未重跑数百CLI、默认性能基准、HTML/截图/PDF或四个源码演示。不新增HTML、跨构建条目匹配、重复内容分析或预算指标，不发布Mooncakes。原图片、AGENTS及规划文件继续排除。

## 24. 按 payload 内容分组的数据段基线比较（2026-10-21）

基线b7a4456。新增compare_data_segments，复用两侧inspect_data_segments和ComparisonError，不修改旧明细报告或analyze签名。完整文件摘要识别产物，payload摘要只分桶；命中后比较长度和实际字节，重复及空payload按次数累计。分组期间仅保留原始范围视图，现有crypto所需临时Bytes副本不进入结果。完整组摘要、索引、次数、payload/条目/元数据总量与差值和两侧明细全部保留，不推断一对一条目身份或初始化语义等价。

--diff-data要求baseline，隐含当前明细，沿用原模式限制与strict/max-size退出契约。baseline文件只读一次，比较的当前明细直接复用，不重复执行inspector。文本按完整条目差值绝对值、完整摘要、长度、发现顺序id确定排序；JSON保留完整发现顺序，不受Top限制。--data-json仅在diff-data启用时写独立moonsize-data-segments-diff/schema_version 1，原单文件格式和公开渲染接口不变；内部提取Json构造函数，没有解析自己的JSON字符串。仍走统一preflight和独占创建，不增加事务保证。

42项定向测试通过，覆盖自比/重排、重复减少、模式和合法非最短宽度变化、内容独有组、空段与空payload、两侧错误、实际字节比较及参数依赖。一次release构建后，原数据脚本扩展为8个CLI场景（只追加成功比较、坏baseline、已有目标三项），全部通过，两个合法输入由V8独立验证。实测data 22→15 B，payload仍6 B，元数据13→6 B，段级开销仍3 B：差值-7 = 0 - 7 + 0；组完整条目差值+2 + 0 - 9 = -7。Top1显示xyz组，完整JSON保留三组。已有目标原字节、两侧输入与旧单文件JSON不变；证据在_build/data-segments-verification/run-KnKfj2，详见[数据段比较](data-segments.md)。

接口审查只增加比较类型/入口、两种渲染及Options.diff_data；现有完整回归和CI数据脚本步骤保留。未在本地重跑性能基准、HTML/PDF或四个源码演示，完整验证以目标提交Linux CI为准。不做字符串/模糊匹配、自动去重建议、offset求值、HTML和新预算指标。相同payload不证明语义等价，重复不证明可安全去重，文件差值不预测重编译或gzip收益。不发布Mooncakes，原图片、AGENTS、规划和构建产物排除。

## 25. HTML 当前输入数据段明细（2026-10-21）

基线eb70927。CLI允许HTML与单文件data选项显式组合，复用一份DataSegmentsReport写HTML和JSON，终端不重复数据表；html+diff-data仍为参数错误。旧render_html保持签名与默认解析成本，新增render_html_with_data_segments，共用模板及一次压缩测量，内嵌可选dataSegments元数据，不放payload内容，不新增分析结论、图表或外部资源。双目标仍统一预检、独占创建，strict和解析错误仍在正常输出前拒绝，不增加事务承诺。

模块位于函数明细后、方法说明前，摘要展示完整data、payload、元数据、段级开销和条目数，datacount单列。静态首屏20条，按payload降序/序号升序；每批追加20条，不默认创建全部DOM。原生details可键盘展开文件范围和未求值表达式；空段、无段及空payload有不同状态。窄屏只在表格内部滚动。打印仅保留当前展示子集及数量，展开已展示详情，结束后恢复，未触发全部条目加载。

71项相关定向测试通过，HTML契约11个CLI场景/7个合法样本通过；只补成功双输出、全部目标预检和解析失败三项进程流程。一次release构建，接口增量只新渲染入口。原fixture路径包含Windows禁用字符及验收脚本局部变量重名已修正，只补跑受影响脚本，不重跑无关回归或默认性能基准。

按AGENTS先启动npm run dev并打开HTTP根入口。真实Edge156.0.4314.36中，45条样本20→40→45、键盘、390px内部滚动、无脚本、图表失败回退与新离线上下文全部通过，无阻断控制台错误。实际A4 PDF打印40/45条，10页经Poppler渲染；人工查看新模块第5–9页和方法续页10及桌面/窄屏截图，数字、文件范围和边界可读，打印后40行及展开状态恢复。证据_build/html-delivery-verification/run-d7HW85；不是对历史PDF全套重新人工验收。详见[HTML交付记录](html-delivery.md)。

正式HTML从原fib输入用CLI生成至新暂存路径，核对输入SHA和全部旧分析字段不变后明确复制更新；新模块252=240+8+4 B、1条。原图片与README截图未动。未做data比较HTML、表达式求值、内容预览或新图表；完整回归与既有演示交给目标SHA Linux CI。本提交不发布Mooncakes，原图片、AGENTS、规划与构建产物排除。

## 26. 0.5.0 发布准备与验收材料（2026-10-21）

以 3af65f3 为功能基线，版本改为 0.5.0，不增加分析功能或调整依赖。迁移说明按公开 0.4.0 对照列出独占输出行为、数据段类型/函数、Options 与 InvalidDataEncoding 分支，以及 HTML 可选数据字段和两种独立 JSON 格式。消费者保留 0.4.0 路径，仅对 0.5 及后续版本追加账本、自比零差值和 HTML 新入口检查。

复制既有数据段测量 JSON、10 页 PDF 与原人工记录并追加附件清单；原附件与哈希不变。新模块人工验收仅第 5–10 页，其余沿用自动检查，不冒充本次重新打印。性能基线未测 50k、峰值内存或真实大型项目，其他浏览器引擎与实体打印机亦未扩大承诺。

本地仅做本次脚本、文档、证据一致性和发布相关定向检查；完整回归由目标提交 Linux CI 执行。实际源码 SHA、CI 数量、仓库外干净包审计、注册表 ZIP 与内容散列、精确版本消费和发布包 CLI 检查分别记入 GitHub v0.5.0 Release，完成前不预写成功。保留旧版发布和历史实验身份，不发布平台二进制矩阵，不代为提交报名材料。

## 27. 修复 Mooncakes 文档构建兼容性（2026-10-21）

0.4.0 与 0.5.0 在线 Build log 均在 bikallem/compress@0.3.4 的 moon.mod.json 处失败；此前锁定 0.10.13 的 CI 与消费检查不覆盖注册表当前文档构建。修补版 0.5.1 去除旧压缩/字节操作/async 依赖链，将固定版本同步 gzip、flate、checksum、blit 的 34 个运行时文件随包携带，记录原始与适配后散列及 Apache-2.0 许可。仅调整包路径、C 符号命名和等价弃用语法，不替换算法或默认参数。

在隔离官方当前工具链 moon 0.1.20261020 / moonc 0.10.16+b1a0e846e 中检查和文档生成通过，仍有非阻断的隐式 trait 方法弃用警告；不为消除警告扩大接口改动。现有工具链 deny-warn 和 18 项压缩测试通过。CI 保留既有回归，增加当前工具链检查、定向压缩测试与 moon doc，另校验 vendored 文件完整性。实际目标 CI、压缩字节对照、公开消费及 Mooncakes 文档状态按完成情况写入 v0.5.1 Release，不以发布上传成功替代文档验收。

## 28. 函数反向引用查询（2026-10-22）

基线2b0db5a，版本仍0.5.1。本次新增 function_callers，复用 parse_module、path_inventory 和 build(data)，按 graph.edges 收集所有命中来源，不经过 analyze、不计算 retained/BFS、不按根可达性过滤。复用 FunctionPathNode/Step，实际解码命中指令并按偏移缓存；固定引用者/位置/kind 顺序，去重相同来源，保留多位置及模块级诊断。旧路径文件和图算法未改。

新增独立文本与 moonsize-function-callers/schema_version1 JSON、Options 两个默认 None 字段。Top 只限制文本组数，JSON与完整计数不截断。CLI 独立分支及英文帮助；strict 在输出预检前拒绝，JSON 继承统一独占创建。新增参数和模式依赖在参数阶段拒绝。

本地只运行 function_callers_test.mbt 的3项组合测试与4个新功能 CLI 场景，均通过；未运行任何旧测试、旧脚本、HTML/PDF、压缩、数据段、预算或源码演示验收。一次必要 release 构建与类型/格式/接口检查属于编译验证。一个136字节混合模块仅V8独立验证一次：导入目标0有3个引用者、7处来源，Top1保留该组4个位置，JSON完整；call_ref84保留为模块级缺口且不猜目标。strict3不创建报告，已有JSON1且字节不变，证据_build/function-callers-verification/run-xgOrRB。

CI仅在既有native构建后追加同一个四场景脚本，完整旧回归继续由既有CI自动执行；成功后只核对目标SHA最终状态。没有新增版本、Mooncakes发布、HTML或递归功能，图片、AGENTS、规划和构建产物继续排除。

首次目标CI在旧数据段HTML测试切换390px后立即检查页面宽度时失败；旧脚本只在切回桌面时等待图表resize。针对失败步骤补上相同的窄屏尺寸收敛等待，保留390px断言、页面与图表代码不变。未在本地执行旧脚本或重做浏览器/PDF验收，修复后的完整验证仍由新目标SHA的CI执行。

## 29. MoonBit 泛型实例编码体积聚合（2026-10-23）

基线d1503a6，版本仍0.5.1。本次先在临时目录构建一次 MoonBit 探针：泛型函数
与泛型方法各使用 Int/Double，均标记 #inline(never)，debug/no-strip 的 wasm
产物经 Node/V8 独立验证一次。原始符号与工具链见 [探针记录](generic-instances.md)。
真实产物45847字节，123个本地定义共17048编码字节；支持范围内2个家族、4个定义
共26字节，另119个有名未分组定义17022字节，账本闭合，不称其为可消除冗余。

新增独立结构化识别，不改旧 display_name/demangle_full；只接受完整且无歧义的
F/M 数字包路径和 Int/Double 参数编码。保留原始家族、参数编码、函数索引，重复
符号的不同索引分别计数，定义数量与不同参数编码数量分开。闭包、trait实现、
未知类型和模糊路径留作未分组。选中的 name 段若无法完整读取，不信任部分名称。

库只调用 parse_module/collect_function_stats，不构图或计算retained。新增文本、
独立JSON及CLI模式，只允许Top/JSON；JSON继承统一预检与独占写入。接口增量仅
4种报告类型、3个入口及Options两字段，无新增WasmError，无旧格式变更。

本地3个新组合测试、4次新CLI调用通过，探针未重建。完成native类型/格式检查、
接口差异审查和一次release构建；未运行旧单测/脚本、HTML/PDF、数据段、压缩、
预算、源码演示或性能基准。本地记录_build/generic-instances-verification/run-uZPaBd
和run-O6ztYa；这些是本机证据位置，不是公开下载链接。CI只追加一个同样构建一次
探针、执行四场景的脚本；旧回归继续由既有CI执行，目标SHA状态在提交推送后核实。

## 30. 导出入口依赖体积（2026-10-23）

基线bc87b54，版本仍0.5.1。本次按函数索引合并全部导出别名，构图一次，每个唯一
入口调用一次既有迭代可达性遍历；全部start/element根合并遍历一次，导出的函数
仍可同时作为其他根。复用path_inventory，不改旧路径、callers、generics、图算法，
不调用analyze或retained。函数归属表只保留一份节点，组和共享表通过索引引用。
导入编码大小保留None，不解释为宿主调用没有成本。错误使用实际名称、序号和
图边指令位置，检查函数导出、根及全部边的索引范围。

新增独立文本、JSON及CLI；Top仅截断两张文本表，别名、汇总和JSON完整，strict
拒绝先于统一输出预检/独占创建。既有WasmError、旧公开签名与报告格式不变，
新增5种类型、4个入口及Options两字段。[接口和实际账本](entrypoints.md)。

本地仅运行entrypoints_wbtest.mbt的3个新组合测试、一次release构建和4次新CLI
调用，均通过；格式、native检查、接口差异审查完成。166字节fixture只经V8独立
验证一次，3个函数导出名归成2组；局部编码账本34=31+3，导出并集31=18+13，
各组可达量26和10不能当作模块体积相加。call_ref98保留模块诊断，strict3不创建
报告，已有JSON1且内容不变；证据_build/entrypoints-verification/run-3bSGHG。

没有运行本地旧套件、浏览器/PDF、源码演示、性能基准，未加HTML、预算或优化
收益推断。CI复用native构建，只追加同一个四场景脚本；完整旧回归由既有CI自动
执行，提交推送后核对目标SHA最终状态，不把本地结果提前写成远程成功。

## 31. 重复函数体字节检测（2026-10-23）

基线ec05025，版本仍0.5.1。本次复用模块/函数范围解析和有界Reader，比较locals
声明加指令的原始body，排除长度前缀。范围检查先于偏移加法与切片；通过有界
Reader读完前缀后取body_offset。类型索引从function段有界读取，仅保留元数据，
不参与分组，也不增加类型/GC解析器或修改Sections。只统计本地定义，索引保留
前置导入偏移；名称可缺失或不同，不影响字节身份。

每个body仅计算一次完整SHA-256，按摘要和长度分桶，再核对实际字节；临时桶
保留原文件视图，摘要接口所需的临时复制不随报告保留。至少两成员才列组，固定
字节总量/长度/摘要/最小索引排序。私有桶函数的强制碰撞测试确认不同正文分开，
没有公开调试开关。比较不调用analyze、图、retained或路径，不归一化，不估算收益。

新增独立文本和JSON、4个类型、3个接口、Options两字段；JSON不包含原始正文，
Top仅截断文本组，完整账本和JSON保留。新JSON沿用统一预检和独占创建。实测
148字节有名称样本：10个本地函数，4组9成员和1单例；body账本30=26+4，完整
编码41=30+11。#8/#9同body但类型0/1、前缀1/2、完整编码5/6，均如实保留。
去掉末尾可选name自定义段得到84字节产物，分组与账本不变。[证据说明](duplicate-functions.md)。

本地仅3个新组合测试、一次release构建及4次新CLI调用，全部通过；完成格式、
native检查及接口差异审查。有名称核心fixture仅V8验证一次，无名称版本只移除
可选name段；未跑旧套件、编译探针、HTML/PDF、演示或性能基准。原始证据在
_build/duplicate-functions-verification/run-fG8XXT。CI只增加同一四场景脚本，旧
回归由既有CI自动执行；提交推送后只核对目标SHA最终结果，不提前宣称远程通过。

## 32. 自定义段与符号名称开销（2026-10-24）

基线0512d61，版本仍0.5.1。新增inspect_metadata及独立文本/JSON模式，不调用
analyze、图、retained或压缩，不改Sections、WasmError及旧名称选择逻辑。每个
custom实例按原文件范围核算段头、名称编码和内容；分类只用严格UTF-8完整名称，
不可用名称单独核算，debug前缀不当成DWARF验证，producers等保持opaque。

遍历全部可靠name段，保留物理子段和id1函数名记录；索引与数量保留完整u32，
重复索引不覆盖。半条失败记录从记录起点记余量，数量失败整个payload记未解析，
无法定界子段从头起记尾部；继续后续可定界子段和custom。坏UTF-8但可定界的记录
保留并继续。原始字节账本、custom名称解码、name解释覆盖分别报告；可选内容
损坏为partial/退出0，外层结构错误仍退出1，不把opaque叫失败或推断可安全删除。

新增9种类型、3个入口及Options两字段，独立JSON不影响旧格式；Top只限制详情，
完整汇总、诊断与JSON保留。参数阶段拒绝strict及其他模式，新JSON接入统一预检
和独占写入。实际123字节样本custom账本115=15+48+52；两个name共61字节，
函数名payload36=3数量前缀+33记录，4条物理记录包含两个重复索引及4294967295。
57字节损坏内容样本仍退出0：name内容35=33已定界+2尾部，映射payload24=3+18+3，
两条诊断及后续later/after记录完整保留。[实际输出与范围](metadata.md)。

本地仅3个新组合测试及4次新CLI调用，全部通过；混合custom核心经V8独立验证
一次。完成格式、native检查、接口差异审查及一次release构建；新接口增量为
计划中的Metadata类型/入口与Options字段。证据_build/metadata-verification/run-SWLCRC。
未跑旧套件、编译探针、HTML/PDF、源码演示或性能基准。CI只追加同一四场景脚本，
旧检查由既有CI自动运行；提交推送后核对目标SHA最终状态，不提前宣称远程成功。

## 33. 宿主导入依赖与编码开销（2026-10-24）

基线6809bd9，版本仍0.5.1。新增inspect_imports及独立文本/JSON，不调用analyze、
图、函数统计或路径；旧count_imported_functions/skip_import_desc未改。复用外层
parse_module与有界Reader，按数量增量读取，恰好耗尽import payload，不按不可信
数量预分配。五种kind分别编号，重复声明不覆盖；module/field严格UTF-8，保留
空名、空白、Unicode及控制字符，文本和JSON正确转义，不解释包、权限或环境。

limits先核对flags再读取UInt数值，支持32位0/1以及memory的有maximum shared3，
检查minimum不超过maximum；typed reference、其他GC、64位和其他flags明确暂不
支持。global mutability和tag attribute具体报错；新增单一InvalidImportEncoding
分支带位置与原因，复用截断、LEB和尾随错误。核心import不采用metadata的partial
成功；解析失败不输出半份清单，不创建报告。

新增7种类型、3个入口、Options两字段及1个错误分支；已审查公开接口增量。
各名称和描述符保留实际范围/前缀，type_index仅声明值，JSON完整u32不变负数。
模块按完整名汇总，段头和count不分摊。Top只截断文本条目，JSON按声明顺序完整
保存，文件复用统一预检与独占创建。[支持范围、迁移与实际输出](imports.md)。

本地仅3个新组合单测及4次新CLI调用，全部通过；152字节五kind混合样本含必要
类型段，Node v24.18.0/V8独立验证一次，不执行。实测import段138=3+2+133，
声明133=64模块名+39字段名+30描述符；模块汇总51+43+24+15=133。memory64在
offset14拒绝、退出1且不创建JSON；已有JSON退出1且原字节不变。证据目录
_build/imports-verification/run-OXjhpk，含输入、四次日志、完整JSON和结果记录。

完成接口生成/差异审查、格式、native检查及一次release构建；本地未跑旧套件、
旧CLI、探针、演示、HTML/PDF或性能基准。CI复用native构建只追加同一轻量脚本，
旧回归继续自动执行；提交推送后核对最终SHA整体状态。本次不改依赖或版本、
不发布Mooncakes，不增加HTML、比较、预算或宿主探测，不预测实际调用或优化收益。

## 34. 宿主导入依赖基线比较（2026-10-24）

基线bc049ce，版本仍0.5.1。新增compare_imports，每侧仅inspect_imports一次并保留
完整清单，不调用analyze、图或函数统计。结构化(module_name, field, kind)键保证
合法名称含分隔符时不碰撞，不以ordinal/kind_index/offset/type_index配对。重复
成员全部计数和保留原序号；交集为数量min，不判定某个重复成员保留或删除。
同名换kind分别移除/新增，same_count不叫未变化或兼容，inventory_changed只看
各键count_delta。类型索引、limits、value_type、mutability及范围留在两侧详情。

新增独立文本和moonsize-imports-diff JSON，Top只限文本组。差值统一current减
baseline，复用ImportsLedger的Int字段，非文件范围；模块段头/count不分摊到组。
--diff-imports要求非空baseline，隐含imports，显式同用允许；单文件imports仍
拒绝baseline，strict及其他模式读取前拒绝。文件复用imports_json槽及独占创建。
两分支比较错误保留原WasmError和侧别，CLI附真实路径、原位置及原因。

接口审查为4种比较类型（含错误包装）、4个入口、Options一字段；旧解析支持、
错误分支及公开签名不变。仅提取私有JSON构造复用完整清单/账本，不改旧格式含义。
实测两侧118/129字节，各9条声明，交集6、新增3、移除3，总数量0但清单变化。
段差11=1段头+1count+9条目，条目差9=1模块名+2字段名+6描述符；重排数量变化0。
[实际哈希、分组和账本](imports.md)。

本地只运行3个新组合测试；首轮其中1个夹具手算期望多计10字节，核对实际条目
后修正，并仅重跑该失败项，三个用例均通过。一次release构建后四次新CLI均通过；
三份合法fixture分别V8验证一次，不实例化/执行。已有JSON返回1且字节不变，非法
侧由API测试覆盖，不新增进程矩阵。证据_build/imports-diff-verification/run-KKoige。
完成格式、native及接口检查；未跑本地旧套件、旧CLI、探针、演示、HTML/PDF或
性能基准。CI保留旧回归，只追加同一轻量脚本；推送后核对最终SHA整体结果。
不扩展类型范围，不增加ABI判断、HTML、预算、自动门禁，不改依赖或发布Mooncakes。

## 35. 数据段重复内容检测（2026-10-24）

基线4966621，版本仍0.5.1。新增inspect_duplicate_data，只inspect_data_segments
一次，保留完整报告和整文件大小/摘要，不调用analyze、图或自比较。每条payload
一次SHA-256，以完整摘要/长度分桶，用data_payload_equal确认实际字节；通过有界
Reader获取临时view，摘要接口所需的临时复制不进入报告，不改旧分组或解析路径。
多个空payload正常成零字节组，单例只计入汇总；组id取最小原始index，排序不
改身份。模式、memory、未求值表达式和实际前缀范围全部由原始明细回查。

新增独立文本和moonsize-data-duplicates JSON、3种类型、3个入口、Options两字段；
Top仅限制文本组，每组预览最多20成员并显示数量，JSON完整。固定组排序为全部
成员payload字节/单份大小降序、最小index升序。新输出接入统一preflight和原生
独占创建，其他模式读取前拒绝；结构错误透传旧WasmError，不扩展旧接口或格式。
字节累计检查后才转Int，避免乘法溢出；不把重复成员总量解释为可删除或节省量。

74字节合法fixture经Node v24.18.0/V8独立验证一次，不执行。三组id0/3/6包含
7成员，另1单例；payload16=13+3，条目51=16+35，data56=3段头+2count+51条目。
DataCount单列，空组仍保留成员6/7及8字节编码；index5与组0等长但内容不同。
[实际哈希、成员范围和账本](data-segments.md)。本地3个新组合单测、四次新CLI均
通过，含私有碰撞注入、21空成员预览、一个错误透传、无data及已有JSON保护。
证据_build/data-duplicates-verification/run-cMyCZN。

完成接口生成/差异审查、格式、native检查及一次release构建；未跑本地旧套件、
旧CLI、演示、探针、HTML/PDF或性能基准。CI只追加同一轻量脚本，保留旧回归，
提交后核对最终SHA整体结论。不做初始化求值、运行时用途分析、自动去重、HTML、
比较或预算，不改依赖/版本，不发布Mooncakes。

## 36. 单函数指令编码明细（2026-10-24）

基线3c29681，版本仍0.5.1。新增inspect_function_instructions，复用parse_module、
collect_function_stats及名称处理，按完整函数索引定位；导入目标明确无本地body。
其他函数仅检查范围，只对目标调用一次有界decode_instructions，不调用analyze、
图、retained或路径。locals范围取第一条解码指令之前的编码，不重复解析locals；
无指令时仍核算已消费范围，不冒充完整语义验证。未知或截断指令透传旧错误。

新增独立文本与moonsize-function-instructions/schema_version 1 JSON，四个入口、
五种公开类型、Options两字段；旧API和WasmError不变。每条保留ordinal、mnemonic、
file/body相对offset及完整编码长度，不保留操作数。组按字节、次数降序及mnemonic
字典序排列；这里显式用lexical_compare，避免默认String.compare的短字优先顺序。
Top限制两张文本表，JSON与汇总完整。其他模式包括strict读取前拒绝，新JSON
接入统一preflight和独占创建，不新增文件写入通道。

90字节fixture经Node v24.18.0/V8独立验证一次，未执行。目标index1在前置导入
之后：entry35=2前缀+33body，body33=3locals+30指令；15条指令、8组覆盖文件
[36,66)，首条block在offset36、相对body3、长度2。两种trunc_sat分别成组。
[实际账本、哈希和范围](function-instructions.md)。原始CLI证据位于
_build/function-instructions-verification/run-zP6iDd，接口快照在review-ekrAGF。

本地仅运行3个新组合单测；初轮2通过/1排序失败，修正字典序后只重跑失败用例
并通过。四次新CLI通过：Top1文本、完整JSON、导入目标拒绝且无文件、已有JSON
保护。完成接口审查、格式和native检查、release构建；补齐usage后增量构建了
最终CLI。未运行本地旧套件、旧CLI、编译探针、演示、浏览器/PDF或性能基准。
CI保留原回归，只追加同一轻量脚本；正常推送后核对最终SHA整体结论。
不增加HTML、WAT、操作数展示、执行频率、完整语义或收益推断，不改版本和依赖，
不发布Mooncakes。用户图片、AGENTS及规划继续排除。

## 37. 本地函数名称检索（2026-10-24）

基线09002f7，版本仍0.5.1。新增search_local_functions，parse_module及
collect_function_stats各一次，复用可选name读取、显示和模块归属标签；不调用
analyze、图、retained或指令解码。只搜索有真实名称的本地定义，使用原query的
大小写敏感字面子串，raw/display分别标记且每个index最多输出一行。同名index
不合并，不把前置导入重编号，不搜索导入或导出别名；占位符不参与，真实名称
为(unnamed)仍可检索。沿用现有名称覆盖边界，不引入metadata补全。

新增独立文本和moonsize-function-search/schema_version 1 JSON、四个入口、三种
公开类型及Options两字段；旧API/WasmError不变。Top只截文本行，计数、字节和
JSON完整。文本转义query、名称和模块中的C0/C1与行分隔符；JSON保持原始值。
无本地函数、无名称、无匹配分别解释且返回0，不能当作不存在或可删除的证明。
新输出接入统一preflight和独占创建；其他模式包括strict在读取前拒绝。

180字节合法fixture由Node v24.18.0/V8独立验证一次，未实例化或执行。query为
classify，匹配index顺序2、3、1；5本地=4有名+1无名，4有名=3匹配+1不匹配。
匹配编码13=9body+4长度前缀字节，index2的前缀宽2，其余各1；offset37明确是
前缀起点。Top1只显示index2，完整JSON仍有全部三个index及原始控制字符名称。
[实测哈希、账本、后续命令和API](function-search.md)。证据目录
_build/function-search-verification/run-9mkQ8G，接口快照在review-JA3JIT。

本地3个新组合单测、四次新CLI全部通过：Top1文本、完整JSON、无匹配返回0、
已有JSON返回1且原内容不变。单测覆盖raw/display、重复名称、字面特殊字符与
Unicode、空白query和占位符、完整账本，以及未知opcode不触发解码。完成接口
差异审查、格式、native检查及一次release构建；未运行本地旧套件、旧CLI、探针、
演示、浏览器/PDF或性能基准。CI只追加同一轻量脚本，保留原回归并核对最终SHA。
不增加正则、模糊匹配、源码/别名搜索、HTML或自动下游查询，不改依赖、版本，
不发布Mooncakes；用户图片、AGENTS及规划继续排除。

## 38. 单函数指令构成基线比较（2026-10-25）

基线16e3d41，版本仍0.5.1。新增compare_function_instructions，用户显式指定前后
两个完整函数index，每侧inspect_function_instructions一次，保留完整报告、文件
摘要、目标身份、范围、顺序指令和聚合。不自动配对、不按ordinal/offset对齐、
不解码其他函数，不调用analyze、图或全模块差异。新错误按baseline/current包装
原FunctionInstructionsError，同时保留用户index和原始位置/原因；不改WasmError。

精确mnemonic并集分别计算次数和编码字节，缺失侧0，零差行仍保留；排序为绝对
字节差、绝对次数差降序及mnemonic字典序。条目/前缀/body/locals/指令/次数差值
统一current-baseline。数量不是文件范围，零统计差不等于序列、立即数或语义相同，
不证明跨构建身份，也不预测性能、重编译或gzip收益。

CLI增加baseline-instructions，必须同时有instructions和非空baseline；缺任一
index均参数阶段返回2，不默认同编号。独立比较只允许Top和自身JSON。成功包括
零差返回0，输入/目标/解码/输出错误返回1，无新退出3门禁。复用原输出槽、统一
preflight及独占创建。旧单文件渲染仅提取私有Json对象helper，字段/值/签名不变；
新比较JSON为moonsize-function-instructions-diff，嵌套完整对象而非JSON字符串。
新增四个入口、四种类型及Options一个字段，接口快照在review-VNxdka。

本地3个新组合单测、四次新CLI全部通过；包含非最短前缀、立即数宽度、重排零差、
扩展opcode分开成行、侧别错误和旧单文件对象一致性。合法前后fixture各由Node
v24.18.0/V8验证一次，未实例化或执行。baseline index1 before-target对current
index2 renamed-current：条目8→12、前缀2→1、body6→11、locals1→3、指令5→8、
次数4→5。差值4=-1+5、5=2+3，全部opcode差求和+3字节/+1条；文件总差+7，
不是条目差+4。Top1不截JSON；自比0差返回0，已有JSON返回1且原字节不变。
[实际SHA、身份和完整账本](function-instructions.md)。原始证据
_build/function-instructions-diff-verification/run-NVyOL3，未为文档另跑名称检索或后续分析。

完成接口、格式、native检查及一次release构建；本地未跑旧套件、旧CLI、探针、
演示、浏览器/PDF或性能基准。CI保留原回归，只追加轻量脚本并核对最终SHA。
不新增HTML、预算、自动匹配、指令对齐、立即数比较或语义判断，不改依赖和版本，
不发布Mooncakes。用户图片、AGENTS及规划继续排除。

## 39. 普通分析的完整JSON导出（2026-10-25）

基线5af51fd，版本仍0.5.1。新增render_summary_json直接读取普通流程同一次
Analysis，不重复解析、analyze、建图、解码、压缩、retained或其他inspector；
整文件SHA-256一次。公开API仅renderer及Options.summary_json，旧类型/签名/
WasmError不变。新moonsize-summary/schema_version 1显式输出input、summary、
全部物理sections、本地functions、符号modules和model，不暴露data、Map/Set、
完整边、未测gzip或预算结论。函数/根按index、模块按完整名称字典序，数组副本
排序不影响Analysis；重复渲染逐字节一致，Top只影响原文本。

retained使用已有值：dominated包含自身、other count不含自身，缺项null；根保留
导入index但不制造导入函数体。复用既有诊断排序和序列化，再以共享说明逻辑给
新格式补reason；caller/opcode/type/table/source及null不丢，原报告格式不变。
诊断数不改写unresolved_count；模型不可达和retained不解释为删除收益，模块是
符号归属标签，函数/模块包含于段，不重复相加。

CLI只允许Top、retained、dead-code、strict、max-size；其他模式读取前拒绝。
写入在原strict拒绝和统一preflight之后、max-size门禁之前，使用原独占writer。
四次真实CLI精确返回3/0/3/1：超限但保存完整JSON、非strict保存动态诊断、strict
不创建报告、已有JSON拒绝且字节不变。合法fixture各Node v24.18.0/V8验证一次，
未实例化/执行。完整样本124=8+116；本地编码16=11body+5前缀，4定义=2可达+2
不可达，编码16=9+7；3模块编码3+4+9=16，根[0,1]含导入。Top1仍有4函数、3
模块、8段。动态样本69字节，静态候选非空、unresolved0、诊断2，table.set及表
导出来源明确区分调用点位置。[实际字段、SHA、JSON账本和退出结果](summary-json.md)。
原始证据_build/summary-json-verification/run-697SsH，接口快照review-JLLIW6。

本地3个新组合单测均通过；初轮2通过，另1因测试误把边界说明中的gzip词视为
测量字段而失败，改为检查实际JSON键后只重跑该用例并通过，未改快照或图结果。
完成接口审查、格式/native检查及一次release构建；未跑旧套件、旧CLI、探针、
演示、浏览器/PDF或性能基准。CI只追加轻量脚本，旧回归保留，核对最终SHA整体
结果。不新增分析、预算门禁或报告合并框架，不改版本和依赖，不发布Mooncakes；
用户图片、AGENTS及规划继续排除。

## 40. 函数与模块基线比较JSON（2026-10-25）

基线6b30b58，版本仍0.5.1。新增render_function_diff_json，直接渲染既有
ModuleSizeDiff，不重新解析、统计、compare_modules、建图或读文件。摘要参数
约定对应同一对输入；CLI用保留的bytes各SHA-256一次，命令包import既有x/crypto，
moon.mod依赖和版本不变。公开API只renderer及Options.diff_functions_json；旧
结构/签名/WasmError不变，接口快照review-ytzt6t。diff_report只更新过时注释，
匹配、包归属和图算法未改。

新moonsize-function-diff/schema_version 1明确输出两侧SHA/file/code、delta、
matching、完整functions/packages和scope。复用change_status_text，五种状态及
重名/无名逐侧记录保留；一侧缺失为null，不造index0。code、函数编码、overhead、
non-code各有账本，matched_delta只解释成功匹配部分；没有新增retained、图完整、
gzip或收益指标，Top不截JSON，自比不按相同摘要强制matched。

JSON选项隐含diff_functions，baseline必填，范围限制只针对新选项，不收紧旧文本
组合。沿用比较→当前分析→strict→统一预检→独占保存→原文本/增长预算顺序，
复用原writer；strict仍仅检查当前图，未新建基线图检查。坏baseline在新模式下
明确加baseline侧别，旧纯文本错误文案不变。max-size配baseline仍按文件增长判断。

本地3个新组合单测通过；类型检查修正了新增变量使用保留字及测试集合方法，
未更改旧实现。两个合法fixture各Node v24.18.0/V8验证一次，未实例化或执行。
baseline112→current128（+16）；code22→29（+7），函数19→24（+5），开销3→5
（+2），非code90→99（+9）。code7=函数5+开销2，文件16=code7+非code9。
匹配覆盖before19=3matched+4removed+8ambiguous+4missing，after24=5matched+
5added+7ambiguous+7missing；matched_delta2不冒充全部函数差5。10条函数变化、
5包标签，唯一匹配index1→3，同名/缺失不合并，自比仍保留不确定单侧记录。
[实际哈希、JSON字段、覆盖与差值账本](function-diff-json.md)。

真实CLI共四次，精确0/3/1/1：Top1完整导出、增长超限仍保存、坏baseline不生成、
已有目标字节保护。初轮第二次已返回3并保存，但脚本文案断言误用绝对预算文本；
改为既有增长提示后只复核前两份记录、继续后两次，没有重跑前两次或V8验证。
证据_build/function-diff-json-verification/run-nq6I4p。完成接口/格式/native检查及一次release构建；
本地未跑旧套件、旧CLI/演示、浏览器/PDF或性能基准，未重复strict进程，只核对
写入前代码位置。CI只追加轻量脚本，保留旧回归并确认最终SHA。用户图片、AGENTS
和规划排除；不改版本、不发布Mooncakes，不新增分析工具或Schema框架。

## 41. 自定义段编码开销基线比较（2026-10-25）

基线cffc252，版本仍0.5.1。compare_metadata每侧只inspect_metadata一次，复用
原始SHA和完整报告，不建图、不再解析/哈希。复用ComparisonError侧别，旧
WasmError、单文件JSON和公开签名不变；新增3种比较结构、3个入口/渲染函数及
Options.diff_metadata，接口差异保存在review-NK0upl。

按固定类别和严格完整名称生成两个替代视图，同名物理实例全部计入，ordinal
仅定位各自输入。名称不可用使用结构化内部键、kind=unavailable_names/name=null，
不与空名、字面标签或U+FFFD混淆。差值用实际前缀宽度；不匹配内容、不配对段，
不比较name内部，不推断语义、可删除性或gzip收益。

实测文件60→62（+2），custom52→49（-3），non-custom8→13（+5）；custom差
-3=段头-1+名称编码-5+内容+3。分类差0/-13/-1/+11/0合计-3，6名称组全部
保留。x的两个实例变一个，编码同为10 B也不称内容相同。partial样本保持外层
完整、诊断及未解析范围，不升级为模块错误。文档及完整JSON见metadata.md和
_build/metadata-diff-verification/run-MYjdpn/。

本地3个新组合单测一次通过，真实CLI恰好4次、状态0/0/0/1，覆盖Top1、完整
JSON、内部partial及已有目标保护。三份合法外层fixture各V8验证一次，不执行。
完成接口/格式/native检查、一次release构建；旧套件、旧CLI、演示、浏览器/PDF
和性能基准均未本地运行。CI只追加轻量脚本，旧回归保留，最终SHA整体状态另行
核对。版本与依赖不变，未发布Mooncakes；图片、AGENTS、规划及构建产物不暂存。

## 42. 导出接口清单与别名分组（2026-10-25）

基线6e04aae，版本仍0.5.1。inspect_exports复用parse_module、有界Reader及一次
SHA-256，只深入export段，不analyze、建图、读取签名、解码函数或调用imports/
entrypoints。旧Export及parse_export_section不变。新Options.exports/exports_json
作为独立模式，只允许Top和自身JSON；统一预检与原生独占创建不另开writer。

严格UTF-8名称保留空白、大小写、空名及Unicode，不demangle；跨kind重复名也
拒绝，诊断同时保留重复和首次声明位置。唯一新增WasmError分支为
InvalidExportEncoding，范围、LEB及尾随错误复用。目标全u32，结构化(kind,index)
键不混淆各索引空间；只证明声明别名，不证明目标存在、类型或可安全删除。

真实126 B五类夹具经Node v24.18.0/V8验证一次，不实例化、不执行。8声明=
5别名成员+3单成员，5目标=2别名组+3单成员；各kind为3/2/1/1/1。export段
57=3段头+2数量+52声明，声明52=35名称编码+17描述符，名称35=9前缀+26 UTF-8，
描述符17=8kind+9索引前缀。函数#0的3声明24 B，表#0的2声明12 B，互不合并。
Top1文本不截JSON的8条目/5目标；控制字符转义，UInt保留4294967295。
[完整范围、实际JSON与迁移](exports.md)。

3个新组合单测一次通过，真实CLI恰好4次、状态0/0/1/1；文本/完整JSON、重复名
拒绝且无文件、已有目标保护均通过。重复样本错误在offset90，首次声明offset74。
完成接口、格式、native检查及一次release构建，接口差异review-5IXIvz；本地
未运行旧套件/CLI、探针、演示、浏览器/PDF或性能基准。证据保存在
_build/exports-verification/run-8yg23B/。CI只追加一次轻量脚本，最终SHA整体状态
在推送后另行核对。版本与依赖不变，未发布Mooncakes；图片、AGENTS、规划及
构建产物不暂存。

## 43. 导出接口清单基线比较（2026-10-25）

基线049c59e，版本仍0.5.1。compare_exports每侧仅inspect_exports一次，保留
原SHA与完整报告，不再解析、哈希、建图或读取类型。按完整名称匹配，不将
kind/index/ordinal混入键；复用ComparisonError侧别，无新增WasmError分支。
新增3种比较结构、3个入口/渲染函数及Options.diff_exports；接口差异review-yeBXtl，
旧签名不变。私有JSON helper提取仅复用对象构造，原单文件字段、类型、值不变。

四类为added/removed/kind_changed/same_kind。同kind索引数字变化是可空布尔值，
跨kind即使同数字也null；缺失侧为null，不伪造声明。双侧别名和范围完整保留，
不做目标组跨构建匹配。报告不评估完整ABI、目标签名、可达性或运行行为，
same_kind不叫“未变化”或“兼容”。

实测文件125→148（+23），export56→64（+8），non-export69→84（+15）；段差
8=1段头+1数量+6声明，声明差6=5名称+1描述符。before7=removed1+kind_changed1+
same_kind5，after7=added1+1+5，完整8行合计声明差6。仅重编号140 B样本相对
125 B基线新增一个前置函数导入，6个函数0→1；same_kind7，其余三类0，export
差0，文件+15全在non-export，不输出ABI结论。[实测账本及JSON契约](exports.md)。

3个新组合单测一次通过；真实CLI恰好4次、状态0/0/0/1，覆盖Top1、完整JSON、
仅重编号及已有目标保护。三份合法fixture各V8验证一次，未实例化/执行；错误
侧别只在单测核对。完成接口/格式/native检查及一次release构建，证据
_build/exports-diff-verification/run-adSfVv/。旧套件/CLI、演示、探针、浏览器/PDF
及性能基准均未本地运行。CI只追加轻量脚本，最终SHA整体状态推送后另行核对；
不改版本和依赖、不发布Mooncakes，图片、AGENTS、规划和构建产物不暂存。

## 44. 按任务查询的命令行帮助

基线190ad88，版本仍0.5.1。新增唯一公开help_request(Array[String])，返回
Ok(Some(text))/Ok(None)/Err(message)。main只取一次argv，在parse_options及
所有文件操作前分发；合法帮助返回0，错误帮助2。无参仍交旧parser返回usage/2，
不往Options加入假path或帮助字段，不改分析和stdout/stderr约定。

只看首个用户参数，精确支持--help、-h、--help-topic；大小写、空白topic、
未知主题和额外参数均按既定规则处理。不扫描后续查询值/输出路径来抢占帮助，
旧parser仍可拒绝其不支持的参数值。七主题以私有结构集中登记ID、标题、摘要、
选项、示例argv、限制和相关主题。完整帮助复用usage，只在原参数表末尾追加
帮助语法和导航，原顺序和说明不变。

本地3个新组合单测一次通过，全部21组主题示例直接调用parse_options确认
参数契约，不反解shell文本、不读文件、不分析；同时覆盖首参数隔离及必要
指标边界。仅一次release构建，4次真实CLI状态0/0/2/2：完整帮助、functions、
未知topic、ci带额外summary-json。每次cwd为空，四次之后仍为空，指定目标
没有创建。实际输出、进程记录见_build/help-topics-verification/run-s9kv1K/。

接口差异仅help_request，快照review-HWwyXt。完成接口、格式、native检查；
未跑旧套件/脚本、源码演示、性能基准，未做Wasm/V8或浏览器/PDF验证，也未
运行探针。本次不需要这些验证。CI保留旧回归，只追加一次轻量帮助脚本，
最终SHA整体结果推送后核对。README仅在长参数表前补七主题导航与原专用文档
链接；[帮助规则](cli-help.md)说明真实语法和边界。版本与依赖不变，未发布
Mooncakes；图片、AGENTS、规划及构建产物排除。

## 45. 未知选项与输入路径边界

基线dbb8c75，版本仍0.5.1。parser只增加私有positional_only状态和兜底前的
未知ASCII短横线标志检查，不改已知选项分支及取值规则。--结束选项解析，
剩余token原样进入唯一输入路径处理；第二个位置参数仍使用unexpected argument。
单个-为文件名，不新增stdin、缩写、--option=value或自动纠错。

help_request、Options、main及分析流程不变；首参数--使帮助层返回未处理，
因此字面--help可作为文件名读取。已被选项消费的值不再判断为分隔符，原query/
输出/负数/baseline校验保留。生成Options后仍经过原模式和输出保护检查。
usage只追加分隔符说明，overview补一条限制，不新增主题或重排原参数表。

本地3个新组合单测一次通过；真实CLI恰好4次，状态2/0/2/0。拼错--summry-json
在I/O前拒绝；-- --help路径正常生成有效summary JSON；分隔符后--top成为额外
位置路径并拒绝，目标未创建；--baseline -before.wasm -- -after.wasm正确比较
两份8 B空模块，文件差0。输入字节全程不变，使用固定八字节头，没有V8检查
或新源码探针。完整argv、日志与JSON见
_build/cli-option-boundary-verification/run-3Oi03W/；[边界说明](cli-help.md)。

完成接口、格式、native检查及一次release构建；.mbti完全无变化，接口快照
review-Vc4pAo。本地未跑旧套件、旧CLI、旧帮助21组示例、演示、浏览器/PDF
或性能基准。CI仅追加轻量脚本，原回归保留，最终SHA整体结果推送后核对。
版本与依赖不变，未发布Mooncakes；图片、AGENTS、规划及构建产物不暂存。

## 46. 数据段UTF-8字面内容检索

基于86e88e8增加search_data_segments，先拒绝空查询，再编码一次并调用一次
inspect_data_segments；私有KMP按payload独立扫描，保留重叠后缀。原字节直接
匹配，不解码payload、不复制候选切片、不建图、不进入analyze。命中按段序号、
段内偏移记录，保留实际SHA-256和完整明细。段数分区及原字节账本不变，
不把重叠长度相加成占用量。新增纯文本/JSON渲染，终端query复用安全转义。

CLI新增find_data/find_data_json两个Options字段，默认为None；独立模式仅允许
Top和自身JSON。参数检查在I/O前，查询分发在普通分析前，只读一次；新目标
复用统一preflight和独占写入。版本0.5.1和依赖不变，未发布Mooncakes。
API审查仅新增DataSearchMatch、DataSearchReport、DataSearchError、检索/描述/
两渲染函数及Options两字段，旧签名和JSON格式不变。

本地仅3个新组合单测通过，覆盖重叠、中文、NUL/无效UTF-8、多段不跨段、
元数据排除、错误/空状态、转义、完整JSON和参数路由；未跑旧套件。真实CLI
恰好4次，退出0/0/0/1，分别为文本Top1、完整JSON、无匹配、已有哨兵目标。
43 B输入SHA-256为31e4561e6e7de6d7c006a71876134e31170ac87bb6313535c297ab7866a18bb3。
查询aa的命中为(段0,段内0,文件18)、(段0,段内1,文件19)、(段1,段内8,文件31)，
长度均2；5条目=命中2+未命中3，3次occurrence。data账本30=payload17+
条目元数据10+段级开销3。脚本从原输入独立核对每条字节与位置；Top1的JSON
仍有全部命中。输入和已有目标字节不变。

证据_build/data-search-verification/run-j7bKMY/保留input.wasm、四份日志、
完整argv/状态、new-search.json和results.json；接口快照review-4f9e823f。
[使用说明](data-search.md)。完成必要接口、格式、native检查及一次release构建。
本地未跑旧CLI/套件、V8矩阵、探针、旧演示、性能、浏览器/截图/PDF。
CI仅追加同一四调用脚本，旧回归保留；推送后核对最终SHA整体结论。
图片、AGENTS、规划和构建证据不纳入提交。
