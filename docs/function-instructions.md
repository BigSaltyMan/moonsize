# 单函数指令编码明细

这是公开0.5.1之后的源码增量；本次不修改版本或发布Mooncakes。

```sh
moonsize app.wasm --instructions 3 --top 20
moonsize app.wasm --instructions 3 --instructions-json new-instructions.json
```

`index`是包含前置导入的完整函数索引，不是code段本地编号或体积排名。
独立模式允许Top和自身JSON；baseline只能配合显式baseline-instructions目标，
详见下节比较。strict及其他分析/输出模式在读取前拒绝，返回2。JSON需要显式
指定目标和新的`.json`路径。输入、越界或导入目标、
解码及输出失败返回1；成功返回0。导入函数没有本地body，不能作为0字节目标。
写入复用统一preflight及独占创建，已有目标不会被截断；未新增事务保证。

## 范围与账本

复用模块结构、函数清单和名称显示，只对选中的本地body调用一次现有解码器。
其他body只检查编码范围，不解码指令；因此本模式成功不证明其他函数指令合法。
不调用analyze、建图、retained或路径查询。无法读取名称时沿用现有未命名展示。

所有范围为原文件的半开区间：

- entry包含函数体长度前缀与body；body包含locals声明和指令。
- locals范围由解码器跳过locals后的第一条指令位置取得，不另行解析或展开locals。
  零locals也有数量字段；无指令时记录整个body为locals编码，不据此认证模块合法。
- 指令的ordinal从0开始，body_relative_offset从body起点计算，包含locals编码。
  encoded_size包含opcode、扩展subopcode及立即数编码，但不展示操作数或常量值。

block、else、嵌套及末尾end都按实际指令记录。0xFC/0xFB扩展沿用现有解码器
支持范围和Opcode.name，不合并不同subopcode，也不增加新的opcode表。
未知或截断指令透传原WasmError；只读当前body，不产生部分成功或借用下一函数字节。
逐条检查正长度、连续性与body末尾，再核对分组账本：

```text
entry.size = prefix.size + body.size
body.size = locals_encoding.size + instruction_bytes
instruction_bytes = sum(instruction.encoded_size) = sum(group.encoded_bytes)
instruction_count = sum(group.count)
```

不包含code段头/数量字段、function段类型索引和name段。Top分别限制文本的
opcode组和文件顺序指令表；显示已展示/总数，不截断账本或JSON，也不是资源限制。
组按编码字节降序、次数降序、mnemonic字典序升序；指令保持文件顺序。

file offset不是内存地址。静态指令数不是执行频率或耗时，locals编码不是运行时
局部变量内存量。文件字节不预测删除、重编译或gzip收益；没有完整类型、控制流、
栈类型或实例化验证，不输出未经计算的graph_complete。

## 可复现样本

`scripts/test-function-instructions.mjs`构造一个合法混合模块，仅由Node/V8验证一次，
不实例化或执行。包含一个导入函数和两个本地函数；目标index1名称为`target"<&`，
使用合法非最短长度前缀、非空locals、嵌套block/loop、不同宽度的i32立即数及
两个不同0xFC指令。脚本保存输入、完整JSON、四次进程日志、CLI/输入散列和环境。

2026-10-24在Windows、Node v24.18.0 / V8 13.6.233.17-node.50、moon 0.1.20260915、
moonc v0.10.13+cbb11c36f下运行。输入90字节，SHA-256：

```text
768c361dbef43f068141ad27b866b8540ff221433d84b95ff22e684b4179283e
```

原始记录位于`_build/function-instructions-verification/run-zP6iDd/`；CI每次运行
创建新的run目录，不复用或覆盖此证据。本地实际文本和JSON共同核对的账本：

```text
Entry: file offset 31, size 35 B
Length prefix: file offset 31, size 2 B
Body: file offset 33, size 33 B
Locals encoding: file offset 33, size 3 B
Encoded bytes: 35 B = prefix 2 B + body 33 B
Body bytes: 33 B = locals encoding 3 B + instructions 30 B
Instructions: 15; grouped bytes: 30 B
```

指令覆盖`[36,66)`，首条block在file offset36、body相对位置3，占2字节。
`f32.const`两条共10字节；`i32.const`两条共5字节；drop四条共4字节；end
三条共3字节；block、loop及两种trunc_sat各一条、各2字节。共8个opcode组。
文本Top1只显示一个组和一条指令，JSON仍保留8组和15条，名称转义后不变。

## 库与JSON

新增inspect_function_instructions(Bytes, Int)，返回FunctionInstructionsReport或
FunctionInstructionsError。新类型FunctionInstructionRange、FunctionInstructionRecord、
FunctionOpcodeGroup及报告仅保存元数据；不输出原始函数体、WAT或操作数。
describe_function_instructions_error保留输入错误原说明，并区分索引、导入目标及
内部范围一致性错误。render_function_instructions(report, top)和
render_function_instructions_json(report)不做第二次解析或解码。

JSON独立使用`format: "moonsize-function-instructions"`、`schema_version: 1`。
包含输入大小和SHA-256、目标身份、entry/prefix/body/locals_encoding范围、
instruction_bytes、instruction_count、完整groups和instructions，以及scope。
每个range含file_offset、size；每条指令含ordinal、mnemonic、file_offset、
body_relative_offset、encoded_size。没有操作数、收益或graph_complete字段。

Options新增instructions_index=None、instructions_json=None，Options::default提供默认值。
旧公开签名、WasmError、已有报告schema不变；外部手工构造Options的代码需补字段。
详见[迁移说明](migration-0.5.md)。

## 显式双目标的编码构成比较

这是公开0.5.1之后的源码增量。需要前后两个文件及各自的完整函数index：

```sh
moonsize after.wasm --instructions 7 --baseline before.wasm --baseline-instructions 5 --top 20
moonsize after.wasm --instructions 7 --baseline before.wasm --baseline-instructions 5 --instructions-json new-instructions-diff.json
```

index7/5在上面仅说明参数位置；实际样本index见下表。可以先分别用--find-functions
取得真实编号，再由用户选择；比较不启动检索，不按名称、相同编号或排名配对。
两个index都必须显式给出，即使编号相同。缺项、负数、非法index或空baseline
路径返回2；单独instructions+baseline也拒绝，不默认同编号。strict、HTML、预算
及其他模式读取前拒绝。新选项不能被其他模式忽略。成功（含增长和零差）返回0；
读取、解析、目标、解码、输出失败返回1，不增加退出3的门禁。

每侧只调用一次inspect_function_instructions，保留其完整身份、范围、指令顺序
和opcode组。沿用现有基础结构和函数边界检查，仅解码两侧选定body，不额外遍历
其他函数的指令。不调用analyze、图或全模块差异分析；任一侧失败整体返回错误，
不输出半份成功报告或创建JSON。导入目标不能当作0字节基线，越界不回退到同名项。

按精确mnemonic取并集，记录两侧count/encoded_bytes及current-baseline差值。
缺失侧为0，不按offset/ordinal对齐，不合并扩展subopcode。次数相同但立即数
编码宽度不同也能有字节差，不根据长度猜立即数值。保留零差行；排序为绝对字节差
降序、绝对次数差降序、mnemonic字典序升序。Top只限制文本opcode行，不影响账本
或JSON。仅比较编码构成统计，未比较指令序列与立即数值；零差不证明序列相同、
语义等价或兼容，相同名称/编号也不证明跨构建身份，名称不同不妨碍比较。

有符号差值只表示数量，不是文件范围：

```text
delta.entry_bytes = delta.prefix_bytes + delta.body_bytes
delta.body_bytes = delta.locals_bytes + delta.instruction_bytes
delta.instruction_bytes = sum(opcode.encoded_bytes_delta)
delta.instruction_count = sum(opcode.count_delta)
```

locals包括向量数量前缀，函数长度前缀保留真实宽度。仍不含code段头/数量字段、
function和name段或依赖闭包；条目差不等于整个文件差，不预测执行速度、源码
删减、重编译或gzip收益。

### 本次实际样本

2026-10-25在Windows、Node v24.18.0/V8 13.6.233.17-node.50、moon 0.1.20260915、
moonc v0.10.13+cbb11c36f下运行；两个合法fixture各由Node/V8验证一次，未实例化
或执行。每个模块有一个前置函数导入及两个本地定义。本次实际命令：

```sh
moonsize after.wasm --instructions 2 --baseline before.wasm --baseline-instructions 1 --top 1
```

用户显式选择：

| 侧别 | 函数index | 名称 | 输入字节 | 条目file offset | body file offset |
| --- | ---: | --- | ---: | ---: | ---: |
| baseline | 1 | before-target | 67 | 31 | 33 |
| current | 2 | renamed-current | 74 | 35 | 36 |

输入SHA-256：

```text
baseline 11e5dfa20f50d8b2e02ef38032554602469d4f7fe0e8339535370660149e435b
current  0b10ba86138daea4ca131889506551b00c12ca4c68ae7ffae1aaa11a87303f19
```

| 指标 | baseline | current | current-baseline |
| --- | ---: | ---: | ---: |
| 条目编码B | 8 | 12 | +4 |
| 长度前缀B | 2 | 1 | -1 |
| body B | 6 | 11 | +5 |
| locals B | 1 | 3 | +2 |
| 指令B | 5 | 8 | +3 |
| 指令数 | 4 | 5 | +1 |

baseline 8=2+6、6=1+5；current 12=1+11、11=3+8。
差值4=-1+5、5=2+3。整个文件增长7字节，与条目增长4字节不同。
按排序的完整opcode差：i32.const字节+3/次数+1，drop +1/+1，nop -1/-1，end
0/0；求和分别为指令+3字节和+1条。Top1只显示i32.const，但JSON仍有四行、
baseline四条指令和current五条指令。两种目标名称不同，仍按显式选择比较。

脚本共四次分析器：文本Top1、同一对目标完整JSON、current index2自比、已有
JSON拒绝覆盖；退出分别0/0/0/1，已有文件保持原字节。自比明确输出零差及统计
边界，不用零差推断序列或语义。原始输入、完整JSON、日志、环境和CLI摘要在
`_build/function-instructions-diff-verification/run-NVyOL3/`。前置名称检索及文档里的后续操作未额外运行分析器。

### 比较API与独立JSON

新增compare_function_instructions(baseline, baseline_index, current, current_index)，
返回FunctionInstructionsComparison或FunctionInstructionsComparisonError。
BaselineInstructionsError(index, cause)和CurrentInstructionsError(index, cause)
包装原FunctionInstructionsError；describe_function_instructions_comparison_error
保留侧别、目标index、原offset及原因。新增FunctionOpcodeDelta和
FunctionInstructionsDelta仅存统计量，Comparison同时保留两份完整报告。

render_function_instructions_diff(report, top)和render_function_instructions_diff_json
不重复解码。比较JSON使用format=moonsize-function-instructions-diff、schema_version=1，
包括baseline/current完整单函数对象、delta、全部opcodes和scope。嵌套对象复用
私有function_instructions_json_value构造器，不嵌入序列化字符串。旧单文件JSON
的format、字段、类型、值和公开签名不变；只有显式比较时共用的instructions_json
输出槽才输出比较格式，继续统一preflight/独占写入。

Options新增baseline_instructions_index=None，默认值由Options::default提供；外部
手工构造Options需补字段。旧签名及WasmError不变，不增加依赖、不修改版本。

## 从指令文件位置查归属（0.5.1后源码增量）

已有指令报告的file_offset可以单独交给`--locate-offset`，例如
`moonsize app.wasm --locate-offset 31`；31只是说明值，应替换为实际位置。
基础查询只确认段、函数前缀/body等文件范围，不重新解码opcode，也不细分locals、
指令和立即数。物理段序号含custom，完整函数index含前置导入。范围为半开
区间，EOF没有字节；独立模式不支持Top/strict或与instructions组合。
[范围、成本和迁移说明](file-offset.md)。

## 文件偏移的可选单函数细化

公开0.5.1之后的源码增量：`--locate-offset 45 --locate-decode`；45为
说明值，应替换为自身位置。基础查询保持原来的function_body归属；启用修饰
后，命中body才调用一次现有inspect_function_instructions，只完整解码目标
函数。结果分locals_encoding或整条instruction，含ordinal/mnemonic、编码范围、
body-relative及条内偏移。opcode、subopcode、立即数不被拆成新指令，也不
进一步识别操作数字段或值；不输出全部指令列表。非body明确not_applicable。
坏目标即使查询locals也返回1、不建JSON、不回退成功；其他函数坏opcode不
影响合法目标。基础接口/九类/JSON不变，修饰模式独立format为
moonsize-file-offset-decoded/schema1。不新增opcode，不认证完整类型/栈/控制流
语义或执行成本。[接口迁移与真实两条定位](file-offset.md#optional-target-function-decoding-source-increment-after-051)。

## 从完整指令明细到调用点清单（0.5.1后源码增量）

单独运行`--calls <index>`可仅列出call、return_call、call_indirect、
return_call_indirect、call_ref和return_call_ref；index为含导入的完整函数索引。
每行保留完整指令序列中的ordinal和真实opcode/偏移/长度，不把过滤后的列表
重新编号。ref.func不是调用，不入表。直接目标附FunctionPathNode，动态目标
保持null；type/table只记录编码，不验证存在性或兼容性，不猜候选。
不先运行instructions再重解操作数；新入口只对目标decode_instructions一次，
全函数成功后才返回。Top仅限制文本，不截断JSON，也不是成本限制。
[API、账本和实测八个调用点](function-calls.md)。

## 只检查locals声明（0.5.1后源码增量）

`--locals <index>`只消费目标body的声明，不先调用指令明细，也不解码任何
函数opcode。保留组、quantity、实际LEB和类型hex；累计声明序号排除参数，
不等于完整local index。余下编码明确为未解码，因此其坏opcode不妨碍locals
查询。与instructions完整解码不同；不能组合使用。
[API、精度约定与字节账本](function-locals.md)。

## 指定双函数的locals比较（0.5.1后源码增量）

`--locals <current-index> --baseline <before.wasm> --baseline-locals <before-index>`
只对两侧声明各检查一次，不进入普通baseline分析，也不解码remainder。两侧
索引都须显式指定，包含导入，不与baseline-instructions混用。按完整type_hex
汇总而非变量匹配，保留零数量组、成员和实际LEB宽度；精确有符号数量差使用
十进制字符串。Top只限制类型行，完整两侧及JSON不截断。与完整指令构成比较
是不同入口，不据零统计差证明语义或剩余内容相同。
[接口、JSON及实测差值账本](function-locals.md#explicit-two-target-comparison-source-addition-after-051)。

## 单独列出local访问（0.5.1后源码增量）

`--local-accesses <index>`使用同一次目标完整解码，筛出local.get/set/tee，保留
完整指令序列的ordinal、文件/body偏移、编码长度及索引编码范围。不先生成
instructions报告再解操作数，也不调用locals查询或构图；其他函数不解码。
按观察到的index稀疏汇总，不按最大index分配数组，tee不重复计get/set。
这里的index包含参数空间，不是locals排除参数的声明序号；不解析签名或绑定
变量，不验证实际范围，沿用现有非负Int上限，不冒充完整u32。目标后部坏指令
仍失败，不返回半份清单。Top分别限制两张文本表，全量JSON不截断。
[API、边界与实测五个访问点](function-local-accesses.md)。

## 全模块汇总（0.5.1后源码增量）

`--opcode-stats`先收集本地函数清单，再每个body解码一次；不循环调用单函数
inspector，不重复解析整个模块。汇总完整指令编码字节、次数和每opcode出现的
不同函数数；不保留全模块逐指令列表、出现位置或opcode×函数矩阵。初始化
表达式不计入，导入无body，任一坏body整份失败并保留完整index及原错误位置。
因此单函数查询成功并不保证全模块可解码。Top不限制全部解码成本，不截断
完整JSON；静态次数不是运行热点。该模式不构图、不算retained，无strict保证。
[code账本、API迁移与真实8组](module-opcodes.md)。


## 全模块指令构成基线比较

`--diff-opcodes --baseline before.wasm`按助记符比较全部本地函数的聚合，
`--opcode-stats-json new-diff.json`保存完整双侧报告。与显式指定两侧index的
`--instructions --baseline-instructions`不同，不选择、匹配函数或对齐指令。
次数差、完整编码字节差和涉及函数数差分开；次数不变时立即数变宽仍可增加
字节，函数出现数不能跨组求和当函数总数。零统计差不证明内容、常量或语义相同。
file/code/non-code与段头/count/前缀/locals/指令账本完整保留；Top只限文本。
[实际+13 B文件差值与迁移](module-opcodes.md#compare-complete-modules-source-addition-after-051)。


## 从opcode查询进入单函数明细

先独立运行`--find-opcode i32.const`，取返回的完整函数index，再用`--instructions`
查看该函数。查询保留全指令序列的ordinal，不按过滤结果重编号；file offset也可
交给`--locate-offset --locate-decode`。这些是分开的命令，不在一次调用中自动
多轮分析。查询检查全部body，单函数inspector仍只解码所选body；立即数和名称
不会伪造命中。Top只限全局命中行，不截断JSON。[实际四位置](opcode-search.md)。
