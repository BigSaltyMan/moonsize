# 按任务查询命令行帮助

这是公开0.5.1之后的源码增量，需构建当前native CLI；版本未变，未发布新包。
帮助不需要Wasm输入，不执行分析，也不创建报告。输出沿用英文。

```sh
moonsize --help
moonsize -h
moonsize --help-topic functions
```

`--help`与`-h`输出完整usage和主题导航，不接受额外参数或topic。查看主题必须
使用`--help-topic <topic>`，精确匹配以下小写ID，不提供缩写或模糊匹配。

| ID | 内容 | 相关文档 |
| --- | --- | --- |
| overview | 普通概览、Top、HTML、summary JSON、压缩口径 | [完整JSON](summary-json.md)、[HTML交付](html-delivery.md) |
| functions | 名称检索、指令、callers、why、retained、重复函数、泛型、entrypoints | [名称检索](function-search.md)、[指令](function-instructions.md)、[callers](function-callers.md)、[入口](entrypoints.md) |
| data | 数据段明细、重复payload、基线比较、HTML当前输入范围 | [数据段](data-segments.md) |
| interfaces | imports、exports及各自基线比较 | [导入](imports.md)、[导出](exports.md) |
| metadata | custom/name字节、外层比较、partial | [元数据](metadata.md) |
| baseline | 文件、函数模块、指定双函数和其他比较入口 | [函数模块JSON](function-diff-json.md)、[实验报告](optimization-experiments.md) |
| ci | max-size、budget、证据输出、支持模式的strict、退出码 | [预算](budgets.md) |

每个主题含简短用途、选项、2～3条主要示例、必要限制及相关主题。路径、查询值、
函数索引和预算均为占位值，不是用户产物的实测结果。输出示例使用新的目标路径；
不能将多个独立查询随意组合。Top限制展示，不截断完整JSON，也不是资源限制。

## 首参数分发与退出码

只有首个用户参数是`--help`、`-h`或`--help-topic`时才进入帮助逻辑，不扫描后续
argv。`help_request`接收的数组包含程序名，所以检查的是args[1]。

- 合法帮助：打印后退出0。
- 缺topic、空/全空白topic、未知ID、大小写不匹配或额外参数：退出2，解释正确
  形式并列出七主题，不读取输入或创建输出。
- 其他调用：交给`parse_options`；其选项与路径边界见下方新增说明，帮助层不抢占业务值。
- 无参数：仍是原usage错误，退出2；没有改为成功帮助。

例如`["moonsize", "app.wasm", "--find-functions", "--help"]`不会触发帮助；现有
查询参数规则仍可能拒绝这个值。输出路径位置出现同样字样也不触发帮助。这不
是在承诺这些业务参数有效，而是保证帮助不会抢占它们。

CLI仅获取一次args，在参数解析及任何文件操作之前调用：

```moonbit
help_request(args : Array[String]) -> Result[String?, String]
```

`Ok(Some(text))`表示已处理，`Ok(None)`表示继续旧parser，`Err(message)`表示
帮助参数错误。库调用者希望获得同样分发时，应先调用此函数；`parse_options`
本身没有新增帮助语义。Options、旧公开签名、分析和stdout/stderr约定不变。

## 帮助内容的边界

完整usage仍是一份原参数表，帮助直接复用它，仅在末尾追加语法及七主题导航。
主题ID、标题、摘要、选项、示例argv、限制与关联集中在私有注册表中；测试直接
将相同argv交给现有parser，不解析展示文本，不引入模板系统、补全或帮助JSON。

主题说明保留真实组合限制：instructions JSON需要目标index，指令比较需显式
指定两侧index及baseline；diff需要baseline，summary JSON不支持baseline。
strict仅适用于支持它的构图模式，并非所有独立清单或查询都能使用。

CI主题区分退出码：0表示完成，部分检查入口可能带partial/未知信息；1为输入、
查询、输出或测量不可用；2为参数/配置错误；3可能是预算超限、strict拒绝不完整
图或路径搜索受限，不能一律称为体积超限。严格模式成功也不证明完整Wasm语义。

相关主题就近说明指标边界：retained、不可达及路径属于当前模型，不预测重编译
收益；独立gzip不可相加、不是网络贡献；重复payload不证明可安全合并；接口清单
不判断完整ABI；metadata外层账本完整可以伴随内部name明细partial。

## 实际输出与验证

本机CLI的完整帮助末尾实际片段：

```text
Help (no input file):
  moonsize --help
  moonsize -h
  moonsize --help-topic <topic>

Available topics (exact lowercase IDs):
  overview  Ordinary analysis and reports
  functions  Find and explain functions
  data  Data payloads and encoding overhead
  interfaces  Host imports and exports
  metadata  Custom sections and name overhead
  baseline  Compare two builds
  ci  Budgets and automation
```

本地3个新组合单测通过；21组主题示例仅验证参数契约，不读取示例文件。四次真实
CLI使用同一个空临时工作目录，日志写到目录之外的验收目录，工作目录始终为空：

| 参数 | 退出码 | 实际结果 |
| --- | ---: | --- |
| --help | 0 | 完整usage与主题入口 |
| --help-topic functions | 0 | 检索、指令及调用/路径入口 |
| --help-topic nonexistent | 2 | 未知主题，列出可用ID，无读取错误 |
| --help-topic ci --summary-json should-not-exist.json | 2 | 额外参数拒绝，目标未创建 |

`-h`、缺参数、精确匹配及业务值隔离在单测覆盖，没有第五次CLI。证据保存在
`_build/help-topics-verification/run-s9kv1K/`，含四份日志和results.json；empty-cwd
始终无文件。本地未跑旧套件/脚本，没有Wasm/V8、源码探针、浏览器/PDF或性能
验证需求，未做这些验证。已有Linux CI保留原回归，仅追加轻量帮助脚本，最终
SHA整体状态在推送后核对。

```sh
moon test --target native help_topics_wbtest.mbt
node scripts/test-help-topics.mjs _build/native/release/build/cmd/main/main.exe
```

## 选项与输入路径边界（公开0.5.1后的源码行为增量）

选项阶段先匹配完整已知参数；未知token以ASCII短横线开头且不等于单个-时，
返回unknown option和帮助入口，退出2。输入已出现后也按相同规则检查未知选项。
不接受前缀缩写或--option=value，不自动纠错。普通第二路径仍报unexpected
argument，而不是unknown option；非ASCII破折号不按ASCII选项前缀处理。

精确token -- 将主循环永久切换到位置阶段，后续每个token都作为原始路径，
不删除前导短横线、不再识别选项。规则如下：

| 调用中的参数 | 结果 |
| --- | --- |
| -- | 缺输入，参数错误2 |
| -- --help | 字面输入--help，帮助入口不处理 |
| -- -- | 第二个--为字面文件名 |
| app.wasm -- | 保留已有输入，末尾分隔符合法 |
| app.wasm -- other.wasm | 第二路径错误2 |
| -- --top 1 | --top先作为路径，1成为第二路径，错误2 |

无分隔符时，普通路径与已知选项仍可按原顺序混排；未知短横线标志不再被隐式
当作输入。读取短横线文件可使用分隔符，或显式相对路径./--name。单个-仍是
普通文件名，不新增stdin支持。分隔符后的文件不存在仍走原读取错误1；不将
全部路径失败改为参数错误。

已知分支已经消费的值不会再经过选项/分隔符判断。--baseline -before.wasm仍
保留原值，负数、query、输出路径及baseline的原有检查不变；原来拒绝--前缀
值的分支不放宽。需要这些值时按原规则使用显式路径，如./--before.wasm。
不全局扫描或删除argv中的--、--help。Options生成后的模式组合、预算配置及
独占输出检查继续执行，分隔符不能绕过它们。

实际验证使用固定八字节空模块0061736d01000000，无源码探针或V8验证；四次
真实argv与退出码为：

```text
--summry-json                                                       -> 2
--top 1 --summary-json new-summary.json -- --help                     -> 0
--summary-json should-not-exist.json -- --help --top 1                -> 2
--baseline -before.wasm -- -after.wasm                               -> 0
```

第二次确实读取名为--help的文件，summary JSON的format为moonsize-summary、
file_size为8、wasm_version为1，SHA-256对应输入原字节，没有进入帮助。第三次
报告unexpected argument --top，没有创建目标。第四次比较两份8 B文件，SIZE
COMPARISON的total为baseline8/current8/delta0。三份输入字节全程不变。

3个新组合单测通过，另检查未知长短标志、缩写、分隔符各边界、值消费和帮助
隔离；没有重跑旧帮助21组示例、旧套件或旧脚本。接口审查确认.mbti完全无变化，
help_request和Options未改。证据位于
_build/cli-option-boundary-verification/run-3Oi03W/，含四份日志、真实argv、
results.json及生成的inputs/new-summary.json。

```sh
moon test --target native cli_option_boundary_wbtest.mbt
node scripts/test-cli-option-boundary.mjs _build/native/release/build/cmd/main/main.exe
```

CI保留已有回归，只追加轻量参数路由脚本；最终SHA整体结果推送后核对。版本
保持0.5.1，不改依赖、不发布Mooncakes；本地未进行旧演示、浏览器/PDF、性能
或额外Wasm算法验证。

## data主题：UTF-8字面内容检索

公开0.5.1后的源码新增`--find-data <query>`和
`--find-data-json <new.json>`；保留七主题，在data中可发现。
例如`moonsize app.wasm --find-data "assets/logo" --top 20`。
独立模式仅允许输入、query、自身JSON和Top；不支持strict、baseline、预算或
其他分析模式。空query非法，单空格合法，值的原有--前缀拒绝规则保留。
首参数帮助与--分隔符不变，查询值不被帮助层全局扫描。

完成查询（含无匹配）返回0，读取/解析/写入失败返回1，参数错误返回2。
按UTF-8字节检索各payload，保留重叠、不跨条目，文件偏移不是内存地址。
Top不截断JSON、不限制查找成本或命中记录内存；查询文字会保存到报告。
[语义、API和验证结果](data-search.md)。

## data主题：有限payload字节预览

保持七主题及每主题三个示例，用一个data示例展示检索后的手动预览；坐标为
说明值。新增`--data-preview <index>`、`--data-offset <n>`、
`--data-limit <n>`和`--data-preview-json <new.json>`。
后三项必须配目标序号；独立模式不支持Top、strict、baseline或其他模式。
默认offset=0、limit=256，上限4096；offset为payload字节位置，末尾空窗口成功，
limit裁到末尾。文本显示小写hex和ASCII，非0x20..0x7e替换为点，不输出控制字节。
JSON完整保存实际返回窗口，而非整个payload；两种报告都包含窗口实际内容。
正常/末尾空窗口返回0，输入/目标/offset/输出错误返回1，参数/limit/组合错误
返回2。严格十进制、未知选项、--分隔符和首参数帮助规则保留。
[完整规则与验证](data-preview.md)。

## overview主题：文件偏移归属

保留七主题及原示例数量，替换一个overview示例展示
`--locate-offset <decimal offset>`与`--locate-offset-json <new.json>`。
示例数字为占位值。独立模式不支持显式Top、strict、baseline、预算或其他业务
选项，JSON要求查询和新的.json目标。严格非负十进制，未知选项/--/首参数帮助
规则不变。偏移必须严格小于文件长度，EOF失败。定位成功0，输入/越界/内部
范围/输出错误1，参数/组合错误2。九类半开区域按命中段细分，不解码opcode，
也不提供完整语义验证或运行时地址；仍需基础结构扫描和整文件SHA。
[完整说明与实测范围](file-offset.md)。

## overview：可选locate-decode

`--locate-decode`必须配`--locate-offset`；复用原JSON输出路径和
互斥规则，仍不允许Top/strict/其他业务模式。七主题和示例总数不变。
默认九类定位和moonsize-file-offset/schema1不变。修饰后body才完整解码目标
函数，locals或整条指令的范围单独保存；立即数和subopcode属于整条指令。
非body明确not_applicable，不解码。坏目标即使查询locals也失败1、不建文件；
成功或不适用0，参数错2。细化JSON为moonsize-file-offset-decoded/schema1，
嵌套原location对象，locals的instruction为null，无全部指令列表或byte_role。
[检查成本、边界及迁移](file-offset.md#optional-target-function-decoding-source-increment-after-051)。

## functions主题：单函数calls

新增`--calls <index>`与`--calls-json <new.json>`；JSON需要主参数，
独立模式只允许输入、Top和自身JSON，不支持baseline、strict、callers、
instructions、locate/decode、search/preview等其他模式。保持七主题和原示例
数量，替换一个functions示例，示例index为占位值。保留严格Int索引、非空.json、
--分隔符、未知选项和首参数帮助规则。成功含零调用0；输入/目标/解码/证据/
输出错误1；参数错误2。导入目标明确拒绝。文本Top只限制调用行，JSON完整。
callers查模型入向引用，calls查目标body调用，ref.func和动态目标口径不同，
不是图反转；calls不构图，无strict保证。[用法和账本](function-calls.md)。

## functions主题：locals声明组

新增`--locals <index>`和`--locals-json <new.json>`，JSON必须有主查询。
独立模式允许输入、Top及自身JSON；显式比较另允许baseline与baseline-locals
成对。其他模式包括calls、locate-decode、data-preview、strict、预算均在读取前
拒绝2；输入/目标/声明/输出失败1，
成功含零组0。保留七主题和原示例数，替换一个functions示例，index是占位值。
原未知选项、--分隔符和首参数帮助规则不变。组数不等于变量数，不展开变量，
累计序号排除参数，不对应完整local index；JSON累计值始终为十进制字符串。
类型hex是事实，标签有限，余下body未解码；Top不截断JSON。
这是公开0.5.1后的源码增量，未重新发布。[范围及迁移](function-locals.md)。

## functions/baseline主题：显式locals比较

新增`--baseline-locals <index>`，必须同时给出locals及非空baseline；locals配
baseline时也必须有baseline-locals。两侧都用含导入的完整索引，不自动配对，
不与baseline-instructions、strict或其他模式混用。参数错2，任一侧输入/目标/
声明或输出错1，成功含自比0。locals-json在比较模式输出独立的
moonsize-function-locals-diff/schema1；单侧格式不变。Top只限制类型汇总行。
完整type_hex是键，零quantity按组存在计入，数量差用精确有符号十进制字符串。
不匹配变量身份，不解码remainder，零差不证明语义或组序列相同。functions及
baseline主题增加入口说明，保持七主题和原示例总数；示例index均为占位值。
公开0.5.1后的源码增量，尚未重新发布。[详情与迁移](function-locals.md)。

## functions主题：local访问编码

新增`--local-accesses <index>`与`--local-accesses-json <new.json>`，JSON需要主查询。
独立模式只允许输入、Top和自身JSON；locals/baseline-locals、calls、locate/decode、
preview、baseline、strict、预算、HTML等在读取前拒绝2。输入/目标/解码/输出错1，
成功含无访问0。首参数帮助、未知选项、--及原参数值限制保持不变。
保持七主题和原示例总数，替换一个functions示例；index为占位值。两张表按
数值index及文件顺序展示，Top各自限制行数，完整成员、汇总和JSON不截断。
访问index包含参数空间，与locals声明ordinal不同；不解析参数/声明绑定，不
校验实际index，当前解码器仅非负Int。静态次数不是热度，大小不是运行时内存
或删除收益。这是公开0.5.1后的源码增量，尚未发布。[用法与迁移](function-local-accesses.md)。

## overview/functions主题：全模块opcode统计

新增`--opcode-stats`及隐含启用模式的`--opcode-stats-json <new.json>`。独立模式
单侧仅输入、这两个选项及Top；baseline只在--diff-opcodes比较时允许。
strict、预算、HTML、单函数查询等在读取前拒绝2。成功含空态0，输入/任一body/输出错误1；坏body不部分成功、不建JSON。
只统计code中本地函数，全部各解码一次，不混入初始化表达式。完整字节包括
subopcode和立即数；function_count每函数内去重，跨组求和不等于函数总数。
结果没有全模块逐指令清单或矩阵。Top只限opcode文本表，JSON含全部函数摘要，
不构图或计算retained，也不限制资源成本。静态次数不是执行频率或运行热点。
overview与functions均补入口/范围，替换一个overview示例；七主题和原示例总数
不变。缺失名称和范围在JSON为null，显示fallback单独保留，原帮助/--规则不变。
公开0.5.1后源码增量，未发布。[使用及迁移](module-opcodes.md)。


## overview/baseline主题：全模块opcode基线比较

新增`--diff-opcodes`，要求非空baseline并隐含opcode-stats，允许显式再给stats。
复用`--opcode-stats-json new-diff.json`，比较格式为moonsize-module-opcodes-diff，
schema1；单侧格式不变。只允许这组模式、baseline、Top和自身JSON，无strict。
示例：`moonsize after.wasm --baseline before.wasm --diff-opcodes --top 20`。
参数错误2；任一侧输入/body/写入错误1；成功含自比0。没有diff的单侧stats仍
拒绝baseline。首参数帮助、--与选项值约束不变。

每侧各检查一次，按mnemonic union比较次数、完整编码字节及涉及不同函数数，
不匹配函数、不对齐指令。完整保留file/code/non-code和code开销拆分；non-code
不等于元数据。零统计差不证明字节或语义相同，function_count差不能跨组求和。
Top只限opcode表，不截断双侧摘要或完整JSON，不是资源限制。保持七主题和21条
示例，只替换一个baseline示例；仍属公开0.5.1后源码增量，尚未重新发布。
[用法、实际账本和API迁移](module-opcodes.md#compare-complete-modules-source-addition-after-051)。


## overview/functions主题：精确opcode位置查询

新增`--find-opcode <mnemonic>`与`--find-opcode-json <new.json>`，JSON要求query。
仅允许本查询、Top、自身JSON和输入，拒绝stats/diff、baseline、strict、预算及其他
查询。缺值/空白query/非法组合在读取前返回2；结构/body/输出失败1；成功含无匹配0。
完整助记符精确、区分大小写，不trim、不支持子串/正则/数值语法；未知名称可无匹配。
首参数帮助、--、未知选项和值约束保持，七主题/21示例不变，只替换一个overview
示例。手动衔接：opcode统计→复制mnemonic查询→以index/offset查函数或原文件。
每body一次解码，只有命中记录留在结果；ordinal来自完整指令序列。Top限全局位置
行数，不是函数组数/资源上限，完整JSON不截断，命中多时结果仍可能很大。
原统计/比较入口和格式不变。公开0.5.1后源码增量，尚未发布。
[匹配规则、API与实际四位置](opcode-search.md)。


## data主题：十六进制payload字节检索

新增`--find-data-hex <hex>`，与UTF-8 --find-data二选一，复用--find-data-json。
仅接受非空偶数位ASCII 0-9/a-f/A-F，不trim，不接受空格/冒号/0x/转义/?/通配符；
大小写等价，报告小写。原UTF-8单空格仍合法。JSON必须有恰好一种query，
hex/text分别使用moonsize-data-hex-search / moonsize-data-search格式，旧格式不改。
输入前参数错误2、输入/输出错1、成功含无匹配0。仍独立，只允许Top和自身新JSON；
未知选项、--与首参数帮助不变。data主题替换一个示例，保持七主题/21示例。
共用KMP事实逻辑、各自构造一次模式，支持NUL/ff与重叠、不跨段、不误搜元数据；
不猜UTF-16或自动转换编码，不输出payload上下文。Top限文本行，不限制完整JSON/
扫描成本或结果内存。模式本身写入报告。公开0.5.1后源码增量，尚未发布。
[实际三命中与API迁移](data-search.md#compact-hexadecimal-byte-search-source-addition-after-051)。


## data/baseline主题：指定双数据段窗口比较

新增--baseline-data-preview与--baseline-data-offset；比较必须有baseline和两侧
显式data-preview index。两侧offset各自默认0、不互相复制，共用data-limit默认256，
范围1..4096，各自min(limit, remaining)。末尾可空，不跨段/补零。缺配对、非法
数字/limit、从属offset或Top及其他模式组合，输入前拒绝2。成功含空窗口0，
输入/任一侧目标或范围/输出错1；原help/未知选项/--规则保持。

复用data-preview-json，单侧moonsize-data-preview不变；比较使用
moonsize-data-preview-diff/schema1，完整双侧对象、位置和计数，缺字节及其文件
偏移为null，不与00混淆。每行最多16位置、最多256行，完整输出、不支持Top。
相同窗口不证明整个payload/资源/文件相同，不自动做插入删除对齐，only不是
语义增删；diff-data仍按完整payload内容分桶。报告包含实际窗口内容。
data/baseline主题已同步，只替换一个data示例，仍七主题/21示例；公开0.5.1后
源码增量，未重新发布。[实际窗口与迁移](data-preview.md#explicit-two-window-comparison-source-addition-after-051)。
