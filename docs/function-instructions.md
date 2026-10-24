# 单函数指令编码明细

这是公开0.5.1之后的源码增量；本次不修改版本或发布Mooncakes。

```sh
moonsize app.wasm --instructions 3 --top 20
moonsize app.wasm --instructions 3 --instructions-json new-instructions.json
```

`index`是包含前置导入的完整函数索引，不是code段本地编号或体积排名。
独立模式只允许Top和自身JSON；strict、baseline、其他分析或输出模式在读取前
拒绝，返回2。JSON需要显式指定目标和新的`.json`路径。输入、越界或导入目标、
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
