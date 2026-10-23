# 重复函数体字节检测

本功能是公开0.5.1之后的源码增量，本次不改版本、不发布Mooncakes。使用当前
源码构建的native CLI：

```sh
moonsize app.wasm --duplicates --top 20
moonsize app.wasm --duplicates-json new-duplicates.json
```

独立模式只允许Top和JSON。JSON隐含启用模式，要求新的`.json`文件；已有文件、
目录或链接别名沿用统一预检与独占创建保护。strict也会在参数阶段被拒绝，因为
本入口不构图。0表示完成（包括零组），1表示读取/结构/范围/输出失败，2表示
参数错误。报告不会修改输入Wasm，也不自动合并函数。

## 比较与范围

只比较FunctionBody.body_size对应的原始字节：**locals声明和指令**。不忽略
locals，不解码后归一化，也不按名称、泛型家族、大小或类型索引归组。

```text
prefix_size = total_size - body_size
body_offset = offset + prefix_size
```

offset是长度前缀的文件偏移，body_offset是locals声明起点，二者均不是内存地址。
实现先用Reader::new_range检查offset/total_size，再检查减法所需的大小关系，
通过有界Reader读过prefix_size后取得body_offset；不先做可能溢出的偏移加法。
函数范围来自现有parse_code_section；function段的type_index按本地定义顺序有界
读取并完整消费，不修改公共Sections，也不增加完整类型或GC解析器。

每个本地body计算一次完整SHA-256，以摘要和长度筛选候选，再检查全部实际字节。
同摘要的不同内容仍分成不同桶，不以摘要作为相等的唯一证明。临时桶保留原文件
视图；当前摘要API要求的一次临时复制不长期保留。公开报告只保存成员范围和
元数据，不含body内容。至少两个成员才输出一组，每个定义最多属于一组。

组按成员body总字节降序、body长度降序、完整摘要升序、最小成员索引升序排序，
成员按完整函数索引升序。摘要碰撞时，成员索引仍可在本次结果中区分组。

## 实际样本

`scripts/test-duplicate-functions.mjs`的有名称样本为148字节；SHA-256：
`c93b92f91e2ff13b6074fc39ac2da0a8e1119b210a065ead0bc2a1c29ff1e64d`。
样本有一个导入函数，因此本地定义使用完整索引#1至#10，不从0重新编号。
它经Node/V8独立验证一次；从同一字节序列只移除末尾可选name自定义段，得到
84字节无名称版本，SHA-256：
`244eb2725f04edaf86479a2f20b620d5217038a0015f2e78a5c2b26c5faec501`。

以下是CLI完整JSON中的实际分组顺序：

| 成员索引 | 单份body B | 成员数 | 成员body B | 前缀合计B | 完整编码B |
| --- | ---: | ---: | ---: | ---: | ---: |
| 8, 9 | 4 | 2 | 8 | 3 | 11 |
| 4, 5 | 3 | 2 | 6 | 2 | 8 |
| 6, 7 | 3 | 2 | 6 | 2 | 8 |
| 1, 2, 3 | 2 | 3 | 6 | 3 | 9 |

第一组完整body摘要为
`036c6d64134ec6c9f1562c1609e5ba30073b08354904767f805fbaf8ec04bc3c`。
其两条成员记录显示：

| index | type_index | offset | body_offset | body_size | prefix_size | total_size |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 | 0 | 68 | 69 | 4 | 1 | 5 |
| 9 | 1 | 73 | 75 | 4 | 2 | 6 |

#9使用合法非最短长度前缀`84 00`。两者名称、类型索引和前缀宽度不同，但比较
范围内的body完全相同，因此归为一组；完整编码大小仍分别保留5和6。类型索引
来自声明，不参与相等判断，也不证明可安全合并。#1/#2同body但名称不同；#4/#6
虽然同名且body等长，正文不同，仍分组不同。#10与最短body组只有相同结束指令，
locals声明不同，所以是单例。

## 完整账本

10个本地函数中，4个重复组包含9个成员，另有1个单例：

```text
Local definitions: 10 = duplicate-group members 9 + singletons 1
Body bytes: 30 B = duplicate-group members 26 B + singletons 4 B
Encoded bytes: 41 B = body 30 B + length prefixes 11 B
```

每组也核对：成员完整编码总量 = 成员数 × body_size + 所有成员前缀字节。
例如第一组11 = 2 × 4 + 1 + 2。duplicate_body_bytes统计组内**全部成员**的body
字节，不是扣掉一份之后的“冗余”或可节省量。41字节不包括code段头、函数数量
字段及其他段，所以不能当作148字节文件的完整组成。导入函数没有本地body，
不会作为零字节成员加入。

无名称版本仍得到相同组和账本，name显示`(unnamed)`、raw_name为null；字节事实
不依赖符号。文本Top1只展示第一组的全部成员，JSON仍包含四组九成员、完整
摘要和账本。Top只影响展示，不限制解析、摘要或逐字节比较的成本。

## 结果边界与接口

相同body字节不证明语义、类型、函数身份等价或可安全合并；没有字节重复也
不证明没有语义重复。零组仅输出`No identical function bodies found.`，不宣称
没有优化空间。本入口不做模糊匹配、指令归一化、跨构建匹配或自动合并，不计算
“总量减一份”，不预测删除、重编译或gzip收益，不计算graph_complete。

```moonbit
inspect_duplicate_functions(Bytes) -> Result[DuplicateFunctionsReport, WasmError]
render_duplicate_functions(DuplicateFunctionsReport, Int) -> String
render_duplicate_functions_json(DuplicateFunctionsReport) -> String
```

复用parse_module、函数范围、function_stats及现有SHA-256；不调用analyze、建图、
retained或路径查询。名称沿用既有可选元数据的显示规则，不影响分组。

新增DuplicateFunctionMember、DuplicateFunctionGroup、DuplicateFunctionsSummary、
DuplicateFunctionsReport；Options新增duplicates=false、duplicates_json=None。
旧签名、Sections、WasmError及原报告格式不变，见[接口增量说明](migration-0.5.md)。
JSON独立使用`format: moonsize-duplicate-function-bodies`、`schema_version: 1`。
成员包含完整索引、名称、raw_name、type_index和范围；组包含完整摘要、body大小、
成员数及body/前缀/完整编码总量。文件身份是实际大小及完整SHA-256，无原始正文
或删除收益字段。

## 定向验证与证据

本地仅运行duplicate_functions_wbtest.mbt中`duplicates:`前缀的3个组合测试：
分组/身份/账本/排序/Top和JSON，私有碰撞复核/无名称/零组/空模块/导入/坏输入及
范围，独立CLI参数。私有碰撞测试不增加公开开关。旧单测或脚本没有在本地执行。

```sh
moon test --target native duplicate_functions_wbtest.mbt
node scripts/test-duplicate-functions.mjs _build/native/release/build/cmd/main/main.exe
```

脚本仅四次分析器调用：有名称文本Top1、同产物完整JSON、去掉name的版本、已有
JSON拒绝（退出1且原字节不变）。新目标成功独占创建；没有扩展路径或链接矩阵。
本地证据在`_build/duplicate-functions-verification/run-fG8XXT/`，含两份输入、
四次日志、完整JSON与results.json；该目录是本机证据身份，CI在新目录复现。
CI复用native构建只增加这一脚本，旧回归由现有CI自动执行。无编译探针、性能
基准、HTML/PDF、源码演示或新的测试框架。
