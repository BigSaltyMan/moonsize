# 本地函数名称检索

这是公开0.5.1之后的源码增量；版本未变，本次不发布Mooncakes。

```sh
moonsize app.wasm --find-functions 'demo::sample' --top 20
moonsize app.wasm --find-functions 'classify' --find-functions-json new-search.json
```

独立模式只允许Top和自身JSON。JSON需要显式query及新的`.json`目标；缺参数、
空或全空白query、JSON无query、其他模式组合均在读取输入前返回2。以`--`开头
的字符串不能作为CLI query参数值；库入口直接接收String，没有此参数限制。
读取、解析或输出失败返回1。检索完成返回0，包括没有匹配、名称不足和空模块。
JSON沿用统一preflight及原生独占创建，不覆盖已有目标，也不承诺多文件事务。

## 匹配和名称覆盖

只搜索本地定义，函数index保留前置函数导入占用的编号。导入声明请用`--imports`；
导出别名不参与搜索。输入只parse_module一次、collect_function_stats一次，复用
现有名称选择、display_name、module_of及SHA-256，不解码指令，不调用analyze或建图。
因此本模式成功不证明函数指令或完整Wasm语义合法。

对raw_name存在的定义分别记录：

```text
matched_raw_name = raw_name contains query
matched_display_name = name contains query
match = matched_raw_name OR matched_display_name
```

规则是大小写敏感的字面子串，不做正则、通配符、Unicode归一化或路径拆分。
`*`、`[`、`.`仅表示自身。trim只判断query是否有效，匹配和JSON保留原始空格。
命中两种名称仍只占一行，来源为raw+display；不同index即使名称相同也全部保留。

raw_name=None时不搜索生成的`(unnamed)`标签。真实raw_name为`(unnamed)`仍可
命中。沿用现有可选name解析，空名称也按原规则视为没有可用名称；不追加metadata
解析，也不承诺名称覆盖完整。三种正常空态分别解释：

- 没有本地函数定义。
- 存在本地函数但没有可用名称。
- 当前可用名称中没有匹配。

名称不是唯一身份；没有匹配不能证明函数不存在。

## 编码账本与展示

```text
local_function_count = named_count + unnamed_count
named_count = match_count + unmatched_named_count
matched_encoded_bytes = matched_body_bytes + matched_prefix_bytes
```

前缀量是各命中函数total_size-body_size之和，包含合法非最短编码的实际宽度。
body含locals及指令；total含body长度前缀，不含code段头/数量、name段及依赖闭包。
offset是原文件中函数体长度前缀起点，不是首条指令地址或内存地址。
匹配量不代表删除、重编译或gzip收益，也不自动推断调用关系。

匹配按total_size降序、index升序排列。Top只限制文本行数，显示已展示/总数；
汇总和JSON始终完整，也不限制搜索成本。文本对query、显示名称、raw和module
标签做引用及控制字符转义；JSON保存原始字符串，不使用终端转义后的内容。

## 可复现样本与后续查询

`scripts/test-function-search.mjs`构造一个带一个函数导入、五个本地定义的合法
样本，仅由当前Node/V8验证一次，不实例化或执行。两个定义使用现有symbol测试
中的`_M0FP34demo6sample3src8classify`，第三个名称带换行、控制字符和中文。
其余定义分别为大写`Classify`和无名称；导入名称也含classify，但不参与匹配。

脚本只调用分析器四次：Top1文本、完整JSON、不匹配query和已有JSON拒绝覆盖。
每次保存进程日志，并保存输入/CLI散列、环境和完整结果。实际测量记录见本节
末尾。下面的后续命令仅供使用，不为文档额外执行分析器：

```sh
# 本样本检索结果中的真实index，换成自己的input和检索结果后使用
moonsize named.wasm --find-functions 'classify' --top 1
moonsize named.wasm --instructions 2
moonsize named.wasm --callers 2
```

用户自行选择index并运行后续命令；本模式不默认选择第一个或最大的匹配。

2026-10-24在Windows、Node v24.18.0/V8 13.6.233.17-node.50、moon 0.1.20260915、
moonc v0.10.13+cbb11c36f下实际运行。输入180字节，SHA-256：

```text
c76049ce00239834a01ce1c2dfc406c850e2bcced85c3e62acc2350b7f26324a
```

query为`classify`；按报告顺序命中index **2、3、1**，两种名称均命中。
5个本地定义中4个有名称、1个无名称；4=3匹配+1不匹配。

```text
Matched encoded bytes: 13 B = body 9 B + length prefixes 4 B
MATCHES: showing 1 of 3 (total bytes descending, index ascending)
INDEX  BODY B  TOTAL B  MATCH SOURCE  NAME
2  3  5  raw+display  "demo::sample::src::classify"
```

完整JSON另含index3（body4、total5）和index1（body2、total3）；index2使用
2字节长度前缀，index1和3各1字节。JSON保留index3名称的原始控制字符内容，
序列化后可还原。index2的offset37是长度前缀起点。不匹配query返回0、匹配字节
为0；已有JSON返回1且原字节不变。原始输入、结果、散列和四次日志位于
`_build/function-search-verification/run-9mkQ8G/`。后续命令使用的index2来自
这份真实检索，未为文档额外调用instructions或callers。

## 库接口和JSON

search_local_functions(Bytes, String)返回FunctionSearchReport或FunctionSearchError。
后者仅包含InvalidFunctionSearchQuery和FunctionSearchInputError(WasmError)，
describe_function_search_error保留原输入错误说明。报告包含输入大小/摘要、原始
query、规则、scope、名称覆盖计数、匹配字节汇总及完整匹配项。

每项FunctionSearchMatch含index、name、raw_name、module_name、offset、body_size、
total_size、matched_raw_name和matched_display_name。raw_name为实际名称字符串；
无名称函数仅进入覆盖统计，不产生匹配项。

render_function_search(report, top)和render_function_search_json(report)不重新
解析或搜索。JSON独立使用`format: "moonsize-function-search"`、`schema_version: 1`，
保留全部匹配和原始字符串，没有操作数、graph_complete或收益字段。

Options新增find_functions=None、find_functions_json=None，默认值由Options::default
提供。手工构造Options需补字段；旧签名、WasmError和已有schema均未改动。
详见[迁移说明](migration-0.5.md)。
