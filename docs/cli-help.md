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
