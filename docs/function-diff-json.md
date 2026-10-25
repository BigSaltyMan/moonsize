# 函数与模块基线比较JSON

这是公开0.5.1之后的源码增量，使用当前源码构建的native CLI；本次不改版本、
依赖版本或匹配算法，不发布Mooncakes。

```sh
moonsize after.wasm --baseline before.wasm --diff-functions-json new-function-diff.json --top 20
moonsize after.wasm --baseline before.wasm --diff-functions --diff-functions-json new-growth.json --max-size 5KB
```

JSON选项隐含开启diff_functions，显式再加文本开关不增加分析。CLI直接复用普通
流程已经取得的ModuleSizeDiff和已读取的同一对bytes，两侧各计算一次SHA-256；
renderer不解析、统计、重新比较、建图或读取文件。命令包增加对已有x/crypto的
import，不增加外部依赖或修改moon.mod。

baseline必须非空，新目标必须是非空`.json`路径。只允许baseline、Top、retained、
dead-code、strict、旧max-size和显式diff-functions文本开关。summary-json、压缩、
其他独立查询/比较、HTML、call-graph、experiment、预算配置/输出、data明细等读取
前返回2。限制仅针对新JSON选项；旧纯文本组合不收紧。

## 输出顺序与退出

```text
既有函数比较成功 → 当前输入分析成功 → 既有strict检查
→ 统一目标预检 → 独占保存JSON → 原文本输出 → 原max-size检查
```

输入、比较、目标或输出失败返回1；成功返回0；strict/max-size沿用3。新增符号、
歧义或未匹配不触发额外门禁。已有文件、目录及链接别名沿用统一保护，不会截断；
没有新增writer或事务承诺。JSON正文不混入stdout，只打印简短保存提示。

baseline配max-size按整个文件增长判定，超限可先保存解释再返回3。strict沿用当前
输入图检查，在预检/写入前拒绝；本功能不计算基线图，不宣称两侧图都已验证。

## 格式、类型和范围

根对象format=`moonsize-function-diff`、schema_version=`1`，包含baseline、current、
delta、matching、functions、packages和scope。没有时间戳、原始bytes、retained、
graph_complete、执行频率或gzip测量字段。数值都是JSON数字，对象不是字符串化JSON。

baseline/current各有sha256字符串、file_size整数和code对象。code有四个整数字段：

| 字段 | 含义 |
| --- | --- |
| code_size | 完整code段编码，缺段为0 |
| function_count | 本地函数定义数，不含导入 |
| function_bytes | 全部本地函数完整条目，含各自长度前缀、locals及指令 |
| overhead | 段头和函数数量编码等段级开销 |

delta所有字段为有符号整数，统一current-baseline：file_bytes、code_bytes、
function_bytes、code_overhead_bytes、non_code_bytes。每侧non_code=file_size-code_size，
包含文件头、name/data及其他段，不代表错误或优化空间。差值不是文件范围。

### 函数与包标签

functions保留ModuleSizeDiff.functions既有排名和全部记录，不因Top截断。每行有
status字符串、raw_name字符串或null、baseline/current对象或null、delta整数。
存在的一侧保留index、name、raw_name、module_name、offset、body_size、total_size，
另有prefix_size=total_size-body_size；数值是整数，raw_name可空，其余名称是字符串。
offset是body长度前缀的file offset，不是首条指令地址。index是含导入的完整编号，
只定位各自文件记录，不能用于跨构建补配。缺失侧是null，不造index0或offset0。

packages完整保留既有PackageSizeChange：name字符串、baseline_functions、
current_functions、baseline_size、current_size及delta整数。它是符号标签推断的
归属，包括未匹配函数，不证明精确源码包或第三方依赖体积。沿用已有排名，不改
模块归属、符号规则或排序算法。

### 五种状态与覆盖

| status | 现有规则含义 |
| --- | --- |
| matched | 两侧唯一原始符号匹配，不能解释成语义身份 |
| added-symbol | 仅current出现的非歧义符号，不证明源码新增 |
| removed-symbol | 仅baseline出现的非歧义符号，不证明源码删除 |
| ambiguous | 原始符号重名，逐侧逐函数保留，不归入added/removed |
| missing-symbol | 无可用原始符号，逐侧逐函数保留，不补配 |

status直接使用已有change_status_text，不维护另一套状态规则。matching完整包含
matched_baseline、matched_current、added_symbols、removed_symbols、ambiguous_baseline、
ambiguous_current、missing_baseline、missing_current八个{count, bytes}整数对象，
以及matched_delta整数。matched_delta只解释成功匹配的部分，不代表全部函数差。

```text
baseline.function_bytes = matched_baseline.bytes + removed_symbols.bytes
                        + ambiguous_baseline.bytes + missing_baseline.bytes
current.function_bytes  = matched_current.bytes + added_symbols.bytes
                        + ambiguous_current.bytes + missing_current.bytes
```

数量按相同互斥分类闭合。不同原始符号不合并；没有按index、显示名、大小或排名
补配。自比仍可能有ambiguous/missing的单侧正负记录：文件总差0不要求每行差0，
不能仅因摘要相同强制matched。名称缺失和歧义未解决，单侧符号也可能来自重命名
或工具链变化。结果不预测未来源码修改、重编译、gzip或传输收益。

## 差值账本与消费

```text
side.code_size = side.function_bytes + side.overhead
sum(package.side_size) = side.function_bytes
delta.function_bytes = sum(function.delta) = sum(package.delta)
delta.code_bytes = delta.function_bytes + delta.code_overhead_bytes
delta.file_bytes = delta.code_bytes + delta.non_code_bytes
```

完整文件差是两个实际输入的原始字节差；函数变化不含name/data等其他段，不能
将函数差或matched_delta冒充完整文件差。code已经包含函数条目，不重复相加。

```js
import fs from 'node:fs';
const report = JSON.parse(fs.readFileSync('new-function-diff.json', 'utf8'));
if (report.format !== 'moonsize-function-diff' || report.schema_version !== 1) {
  throw new Error('Unsupported function-diff format');
}
for (const row of report.functions) {
  console.log(row.status, row.baseline?.index ?? null, row.current?.index ?? null, row.delta);
}
console.log(report.matching, report.delta, report.packages);
```

## 库接口

render_function_diff_json(diff: ModuleSizeDiff, baseline_sha256: String,
current_sha256: String)->String仅渲染已存在结果。**调用方必须保证摘要来自生成diff
的同一对输入**；renderer没有bytes，不能核验摘要是否对应文件。CLI使用保留的
bytes保证此约定，不重读文件或再次compare_modules。重复渲染相同diff与摘要逐
字节一致，原比较数组及数据不改变。

Options新增diff_functions_json=None，默认值由Options::default提供，外部手工构造
需补字段。仅新增renderer及此字段，ModuleSizeDiff、旧签名、WasmError和其他JSON
不变。旧文本入口仅更新“仅文本首版”的过时注释。见[迁移说明](migration-0.5.md)。

## 本次实际验收

2026-10-25在Windows、Node v24.18.0/V8 13.6.233.17-node.50执行。两侧都含一个函数导入和
仅由locals/NOP/end构成的合法本地函数；每个合法fixture各经Node/V8验证一次，
未实例化、未执行。坏baseline的版本2头部是故意非法输入，不作为合法样本验证。
原始输入SHA-256：

```text
baseline 883ac2f2f8259655d09bfb892bf962367e650af52636b00ba744542839109b6c
current  b68c49f0dcd8aaecb90dc07652aaa05571d9d17e10381e6de3230cd81a8b9922
```

| 指标 | baseline | current | current-baseline |
| --- | ---: | ---: | ---: |
| 整文件B | 112 | 128 | +16 |
| code B | 22 | 29 | +7 |
| 函数编码B | 19 | 24 | +5 |
| code overhead B | 3 | 5 | +2 |
| 非code B | 90 | 99 | +9 |
| 本地函数数量 | 5 | 6 | +1 |

两侧22=19+3、29=24+5；差值7=5+2、16=7+9。current的code段长度和数量字段
使用合法非最短编码，段级开销确实从3变5；不是把这2字节归给某个函数。
packages按排名为new、old、(unnamed)、pkg、dup；函数编码分别0→5、4→0、4→7、
3→5、8→7，总和19→24，差值5=5-4+3+2-1。

| matching类别 | baseline数量/B | current数量/B |
| --- | --- | --- |
| matched | 1 / 3 | 1 / 5 |
| removed / added symbols | removed 1 / 4 | added 1 / 5 |
| ambiguous | 2 / 8 | 2 / 7 |
| missing | 1 / 4 | 2 / 7 |

baseline 19=3+4+8+4，current 24=5+5+7+7；数量5=1+1+2+1、6=1+1+2+2。
唯一匹配raw含引号、换行和中文，index从1到3；matched_delta=2，不等于全部函数
差5或文件差16。完整JSON有10条函数变化、5个包标签，Top1不丢歧义或无名记录。
名称序列化后可还原，缺失一侧仍为null。单测自比保留6条歧义/无名正负记录，
其和为0；不会把这些记录强制改成matched。

| 真实CLI场景 | 精确退出码 | 文件结果 |
| --- | ---: | --- |
| baseline + 新JSON + Top1 | 0 | 完整JSON，文本汇总与112→128、19→24一致 |
| 同一对输入 + 显式diff-functions + max-size 0B | 3 | 增长16B，JSON先保存且内容一致 |
| 版本2的坏baseline | 1 | 明确baseline错误，不创建新JSON，无成功表格 |
| 正常输入写已有JSON | 1 | 原字节保持，无错误成功提示 |

四次真实分析器调用已经完成。初轮前两次返回了预期0/3，但测试误用绝对预算
文案断言；增长原文是“grew by 16 bytes over the baseline, budget 0 bytes”。修正
该断言后，仅复核前两次日志/JSON并继续后两次调用，未重复分析或验证输入。
原始脚本、修正后的续跑记录、输入、完整function-diff.json/growth.json和日志在
`_build/function-diff-json-verification/run-nq6I4p/`。CI使用修正后的常规脚本一次执行全部四场景。

本地仅3个新单测、上述四次CLI、必要接口/格式/native检查和一次release构建；
strict仅核对同一写入前检查的位置，未新增第五次CLI、未重跑旧strict或其他旧
套件/演示、浏览器/PDF和性能基准。旧回归交给目标提交Linux CI。
