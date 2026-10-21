# 复审证据入口 · 0.5.0

先读[项目说明](october-proposal.md)、[针对原驳回理由的回复](october-review-response.md)。
本页按评审问题组织，可直接阅读仓库文件；CI 附件提供更完整的重跑记录，
不是唯一证据。[0.5.0 发布记录](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.5.0)
在各步骤实际完成后记录对应 SHA、目标 Linux CI、注册表 ZIP 校验和及精确版本消费结果；
[0.4.0 历史发布](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.4.0)不作为本轮成功凭据。

## 指标究竟证明什么？

| 评审问题 | 结论与可读证据 | 实现 / 可复现入口 |
| --- | --- | --- |
| retained 等于真实减量吗？ | [定义及五组样例](retained-size-boundaries.md)、[原始测量 JSON](retained-boundaries-results.json)。固定图的受支配函数编码权重不提供真实收益的通用上下界。 | [支配计算](../graph.mbt)、[源码](../examples/retained-boundaries/)、[重建脚本](../scripts/demo-retained-boundaries.mjs) |
| 共享依赖怎么算？ | shared debug：R=16 B，重建减量127 B，整文件 gzip减量41 B；shared 在 after 存活。不是把共享函数当独占成本。 | 同一脚本的 shared-before/after；保存输出并回退核对 |
| 为什么函数可达？ | [实际路径 JSON](review-artifacts/function-path.json)、[源码演示测量](review-artifacts/function-path-results.json)。根47经35到36，含 export 来源及两个指令偏移；索引仅属于该产物。 | [确定性 BFS](../function_path.mbt)、[演示源码及发现索引流程](../scripts/demo-function-path.mjs) |
| 怎样确认优化效果？ | [实验 JSON](../examples/optimization-experiment.json)、[HTML 源文件](../examples/optimization-experiment.html)、[解释及命令](optimization-experiments.md)。数据/整文件 gzip 实测与调用者声明分开。 | [实验实现](../experiment.mbt)、retained 演示构建/执行/回退 |
| 如何阻止 CI 回归？ | [四指标测量](review-artifacts/budget-results.json)、[通过](review-artifacts/budget-passed.json)、[超限](review-artifacts/budget-exceeded.json)，退出精确0/3，回退一致。 | [预算定义](budgets.md)、[源码演示](../scripts/demo-budget.mjs)、[CI](../.github/workflows/ci.yml) |

独占 debug 的固定样例：R=52 B、真实文件减量656 B、完整 gzip 减量237 B；
独立段 gzip 合计5371 B、整文件5236 B。**样例反驳等同关系，不建立所有文件
的比例或不等式。** `strict` 成功也不是精确收益、业务正确或完整 Wasm 验证证明。
不可达是调查候选，路径是模型引用而非执行轨迹。

数据段新增证据：[22 B 账本 JSON](review-artifacts/data-segments.json)、
[22→15 B 比较 JSON](review-artifacts/data-segments-diff.json)、[定义与复现](data-segments.md)。
比较差值 -7 = payload 0 + 元数据 -7 + 段级开销 0；按实际字节分组，不推断条目身份、
初始化语义等价或去重收益。[性能基准](performance.md)仍未测 50k、峰值内存及真实大型项目。

## 源码、输入与重跑方式

测量快照保留实际工具链、输入和源码 SHA-256，不手改结果。路径/预算快照为
2026-10-16 Windows x64 本轮重跑：moon 0.1.20260915、moonc
v0.10.13+cbb11c36f、Node 24.18.0；固定 wasm/debug/no-strip，函数身份用
`#inline(never)` 保留。retained 快照另有 release 对照及明确标注的人工 Wasm 控制。
源码实现基线为 [3a07e03](https://github.com/BigSaltyMan/moonsize/commit/3a07e035b4e0de914f43d1eeac43c19497522914)；
上述快照属于此前 0.4.0；当前 0.5.0 功能基线为
[3af65f3](https://github.com/BigSaltyMan/moonsize/commit/3af65f3316a397a8415b5789015af748ff7a7830)。
本次仅整理版本、材料和消费回归，不新增分析功能。

```sh
moon build --target native --release
CLI=_build/native/release/build/cmd/main/main.exe
bash scripts/demo-function-diff.sh "$CLI"
node scripts/demo-retained-boundaries.mjs "$CLI"
node scripts/demo-function-path.mjs "$CLI"
node scripts/demo-budget.mjs "$CLI"
```

本地输出目录是复现结果，不是线上评审入口。JSON 内的绝对路径保留原测量身份，
并不作为链接。源码演示脚本提供原始源码/构建命令、实际执行输出及字节一致的
rollback 检查；路径目标由构建产物发现，不硬编码编译器索引。
案例有意删/增可选输出，检查基础输出，**不是完整行为等价**；必须运行自己项目
的业务检查，文件变小不能自动算作正确优化。整文件 gzip 仍只是本压缩器配置下
的表示体，不测部署编码、HTTP/TLS、缓存或实际网络成本。

## HTML 可以独立交付和打印吗？

| 能力 | 已有证据 | 未扩大承诺的边界 |
| --- | --- | --- |
| 任意 cwd 生成 | [发行与复现说明](html-delivery.md)、[环境/哈希快照](html-delivery-results.json)、[资源来源和许可](../assets/README.md)。空 cwd 和同名恶意 assets 下实际 CLI 输出一致。 | CLI 编入 ECharts；库 `render_html` 默认空资源仍为 CDN，调用者须主动传源。 |
| 迁移后离线渲染 | 关闭原上下文，复制件哈希一致；新上下文创建时即断网，只映射主 HTTP 文档，零外部请求及阻断错误，四图/tooltip/表格正常。 | 没有测试 OS 双击 `file://`，没有使用原标签缓存证明断网。 |
| A4 PDF 可读 | [example.pdf · 5页](review-artifacts/example.pdf)、[long-name-warning.pdf · 4页](review-artifacts/long-name-warning.pdf)、[全部9页人工检查记录](review-artifacts/pdf-page-review.md)。 | Edge 156.0.4314.23 / Windows 10.0.26300 / Playwright1.58.2 / Poppler26.07.0，A4纵向12mm。非Chromium和实体打印机未验证。 |

新增 [data-entries.pdf · 10页](review-artifacts/data-entries.pdf) 与
[原定向人工记录](review-artifacts/data-entries-page-review.md)直接复制自 run-d7HW85。
Edge 156.0.4314.36 / Windows 10.0.26300 x64 / Playwright1.58.2 / Poppler26.07.0；
45 条输入哈希与 PDF 哈希见清单。PDF 只打印当时展示的 40/45 条，第 5–10 页人工检查，
第 1–4 页沿用自动检查，不宣称本次重新验收。

两个历史公开 PDF **直接复制**自已验收的 run-JM2Zrx，文件名来自现有记录；其哈希与
[原始验收快照](html-delivery-results.json)一致。它们是历史本地人工验收证据，
不冒充本次提交的干净 CI PDF。PDF 图表、完整名称、关键数值、诊断与模型/压缩
边界均保留；打印后布局和折叠状态恢复。所有公开附件见
[清单及 SHA-256](review-artifacts/manifest.json)。

```sh
npm ci
npx playwright install --with-deps chromium
# Ubuntu另装 poppler-utils fonts-noto-cjk；Windows环境变量见交付说明
npm run dev  # 保持运行，http://localhost:5173/
node scripts/test-html-portability.mjs "$CLI" --browser
```

这会重新生成实际断网记录与 PDF。CI 自动检查不称为人工逐页验收。
[此前3a07e03成功CI](https://github.com/BigSaltyMan/moonsize/actions/runs/38911605287)
仅证明此前基线；本轮目标 SHA 的独立 CI 链接位于发布记录。

## 公开版本和验收链

旧公开0.3.0包实际不含本轮成果，已按下载 ZIP 对比 API；
[0.4.0迁移说明](migration-0.4.md)列出签名变化、诊断、Options、模式约束和独立
JSON版本。不是“无破坏变化”。历史精确版本命令：

```sh
node scripts/verify-release-consumer.mjs 0.4.0 consumer-result.json
```

0.5.0 使用 `node scripts/verify-release-consumer.mjs 0.5.0 consumer-result.json`，
在注册表发布后验证数据账本、自比零差值及 HTML 新入口；成功状态只在发布记录中确认。
[0.5 迁移说明](migration-0.5.md)列出相对公开 0.4.0 的变化。

独立消费项目从 Mooncakes 安装，编译并实际执行 parse/stat、尾调用路径、差异、
实验和预算0/3，不引用开发工作区。发布记录连接“源码SHA → 该SHA CI → 干净
导出与包清单 → 注册表校验和 → 精确版本消费”。大型临时产物留在 CI 附件，
本页保留足够的源码、测量和PDF供直接审阅。不增加性能、大模块规模或完整语义
验证承诺，不预测复审是否通过。
