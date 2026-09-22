# EikoHelp

**浏览器里的电商智能客服 Agent。** FastAPI + LangGraph + MySQL + Milvus：能查订单物流、答政策 FAQ、走退款子流程、从对话里挖知识补库，还带一个微调出来的主题分类器。项目从一个纯对话接口起步，按 ch01 → ch10 十个阶段逐步迭代，长成现在这套东西。

架构上只守一条：**上游直连，不设网关。** 聊天、嵌入、重排三组模型各自直连，模型名和地址全在 `.env` 里配，换供应商、换模型不用改代码。

问一句「订单 1001 的物流到哪了」，Agent 自己决定调哪些工具，回答带依据：

```
你: 订单 1001 的物流到哪了
 ├─ ⚙ query_order(1001)        → 订单存在，已发货
 ├─ ⚙ query_logistics(1001)    → 包裹运输中，预计明天送达
 └─ 已发货，包裹运输中，预计明天送达……
```

## 特性一览

| 能力 | 一句话说明 |
| --- | --- |
| 流式对话 + 结构化提取 | SSE 流式回复，意图 / 指代 / 摘要全走结构化输出 |
| Function Calling 工具 | 五个内置 `@tool` 业务工具，单轮即可触发 |
| RAG 知识库 | 切块、嵌入、MySQL 与 Milvus 双写、去重、对话挖知识 |
| 混合检索 | BM25 + 向量 → RRF 融合 → 重排，Query 改写，四策略可评估 |
| LangGraph Agent | workflow 骨架 + ReAct 环，分流器路由，退款走 interrupt/resume 子流程 |
| 上下文管理 | 滑窗、摘要、前缀缓存，token 预算可控 |
| MCP 工具系统 | 业务 MCP Server 动态发现，统一执行引擎 + 审计日志 |
| 可观测 + 数据飞轮 | Langfuse 自部署、置信度门限、按意图算成本账 |
| 主题分类器 | 语料流水线 → 微调 → 阈值扫描 → ONNX 推理服务 |

## 安装

需要 [uv](https://docs.astral.sh/uv/)（Python 版本不用自己装，uv 会拉）和 Docker；内存 8G 起、磁盘 10G 起。

```bash
uv sync
```

## 配置（只需做一次）

```bash
cp .env.example .env
```

编辑 `.env`，填三组密钥（用同一家上游就填同一个值，默认按硅基流动给的，注册一个账号就能跑通全部功能）：

```bash
CHAT_API_KEY=sk-xxx
EMBED_API_KEY=sk-xxx
RERANK_API_KEY=sk-xxx
```

- 模型名必须是上游认的真实模型名——没有网关就没有别名这一层，写错会被上游拒
- 换供应商只改 `*_BASE_URL` 和 `*_MODEL`，比如换成 DeepSeek 官方：`CHAT_BASE_URL=https://api.deepseek.com/v1`
- 凭据只在 `.env` 里，已被 `.gitignore` 覆盖，不会进 git

## 运行

```bash
docker compose up -d      # MySQL / Milvus / MinIO / etcd，首启自动建表+灌种子数据
make kb-build             # 知识库切块落 MySQL
make kb-vectorize         # 向量化写进 Milvus（调嵌入接口）
make dev                  # 依赖容器 + MCP :8101/:8102 + 应用 :8000
```

浏览器打开 <http://localhost:8000> 就是聊天页。

**Windows 图省事**：双击根目录的 `启动EikoHelp.bat` 起服务并打开聊天页，`打开后台管理.bat` 打开后台管理页（服务已在跑时不会重复起进程）。

验收装好了没有：

```bash
printf '{"user_id":"u1","message":"订单 1001 的物流到哪了"}' > /tmp/q.json
curl -s --max-time 90 http://localhost:8000/api/agent \
     -H 'Content-Type: application/json' --data-binary @/tmp/q.json
```

返回 JSON 的 `tool_calls` 里有 `query_order` 和 `query_logistics`、`answer` 里有物流状态，就是部署成功了。完整的逐步部署手册（含每步验收标准）在 [DEPLOY.md](DEPLOY.md)——它也可以直接丢给 Claude Code、Cursor 之类的工具，说一句「按 DEPLOY.md 把项目部署起来」就行。

## 页面一览

| 页面 | 作用 |
| --- | --- |
| `/` | 聊天页 |
| `/admin` | 后台管理 |
| `/kb` | 知识库录入 |
| `/review` | 飞轮待审 |
| `/observability` | 观测与成本 |
| `/topics` | 主题分布 |
| `/acceptance` | 分类器验收 |

## Agent 是怎么工作的

一张 LangGraph 图撑起整个对话：分流器先路由，指代消解和 Query 改写做预处理，主力 Agent 跑 ReAct 环调工具，退款这类有确认环节的流程走 interrupt/resume 子流程，上下文用滑窗 + 摘要 + 前缀缓存控制在预算内。

内置五个 `@tool`，外部工具走 MCP：

| 工具 | 来源 | 作用 |
| --- | --- | --- |
| `query_order` / `query_product` | 内置 | 查订单 / 商品（按 user_id 稳定生成的模拟数据，任何账号名下都有 1001 和 2002 两笔演示单） |
| `query_faq` | 内置 | 查 FAQ，走 RAG 检索 |
| `create_ticket` / `submit_refund` | 内置 | 建售后工单 / 发起退款 |
| 物流 / 售后工具 | MCP `:8101` / `:8102` | 两台独立进程的业务 MCP Server，动态发现后与内置工具无差别调用 |

所有工具经统一执行引擎执行，留下审计日志；工具循环的每一步在聊天页都有标记，看得见 Agent 做了什么。

## 知识库与检索

知识从两个方向进库：`/kb` 页面手工录入，或从历史对话里自动挖问答对（挖出来的先进待审队列，人审过才入库）。入库统一走「切块 → 嵌入 → MySQL + Milvus 双写 → 去重」。

查询侧是四段流水线：BM25 与向量各查一路 → RRF 融合 → 重排 → 按策略取 Top-K。四策略（纯向量 / 纯 BM25 / 混合 / 混合+重排）都能跑评估出对比报告。

## 可观测与数据飞轮

- **Langfuse 自部署**（`make langfuse-up`）：全链路 trace 落本地，不上传任何数据
- **置信度门限**：低置信回答自动挂「待复核」，复核结果回流成评估样本
- **成本账**（`make cost-report`）：按意图维度统计 token 花费，`/observability` 页面看趋势

## 主题分类器

ch10 的完整闭环：捞对话池 → 清洗预标 → 人工抽审 → RoBERTa-wwm-ext 全参微调 → 阈值扫描定容错红线 → 导出 ONNX 起 `:8110` 推理服务 → 对新对话旁路批量归类。训练重依赖（torch 等）走 `uv run --group ml` 按需装，主应用运行时不需要。

## 迭代历程

`make test` 跑全部单测，不打真实模型；下面这些验收命令要真服务在跑。

| 章 | 长出来的东西 | 验收 |
| - | - | - |
| ch01 | 流式对话、结构化提取 | `make eval` |
| ch02 | 五个 `@tool` 业务工具 | `make eval-agent` |
| ch03 | 切块、嵌入、双写、对话挖知识 | `make kb-build` `make kb-vectorize` `make eval-retrieval` |
| ch04 | 混合检索、RRF、重排、四策略评估 | `make smoke-rag` `make eval-rag` |
| ch05 | LangGraph 骨架 + ReAct 环 | `make eval-ch05` |
| ch06 | 分流器、指代消解、interrupt/resume | `make smoke-interrupt` `make eval-ch06` |
| ch07 | 上下文管理 | `make eval-ch07` |
| ch08 | MCP 动态发现、统一执行引擎 | `make eval-ch08` |
| ch09 | Langfuse、数据飞轮、成本账 | `make langfuse-up` `make flywheel` `make cost-report` |
| ch10 | 主题分类器 | `make ch10-corpus` `make ch10-train` `make ch10-eval` |

每条命令的前置条件用 `make help` 看，每个目标都带说明。

## 设计取舍

- **三上游直连，不设网关。** 少一层抽象，配置即换供应商；代价是没有统一别名和兜底，模型名要写上游认的真名
- **MySQL + Milvus 双写。** 结构化数据和向量各归各家，去重靠 MySQL 侧约束
- **演示业务数据不落库。** 订单和物流按 user_id 确定性生成，谁 clone 下来都有一样的演示单
- **单测不打真实模型。** `make test` 全离线跑，评估类命令才需要真实上游
- **spec 和 plan 留在仓库里。** `docs/superpowers/` 是每个阶段动手前写的 spec 和 plan，从设计到验收的流程自洽，留着当范本

## 故障排查

**镜像拉不下来（国内常见）**
Docker Hub 和 quay.io 经常连不上。先拉镜像站再打回原名，`docker-compose.yml` 一个字不用改，具体命令见 [DEPLOY.md](DEPLOY.md) 第 3 步。

**`docker compose up` 起不来，报 3306 冲突**
本机已有别的 MySQL 占着 3306。停掉那个容器或改端口映射，二选一自己定。

**只有 `answer` 没有 `tool_calls`**
模型没触发工具调用，通常是 `CHAT_MODEL` 写的名字上游不认，或中转端点拿了别的模型应答。回 `.env` 核对模型名。

**头半分钟 MinIO 显示 starting**
正常。Docker 每 30 秒才做一次健康检查；一直 unhealthy 才是真出问题。

**Windows 下 `uv run uvicorn` 报 `trampoline failed to canonicalize script path`**
路径含中文时 uv 的 trampoline 启动器会挂。用 `uv run python -m uvicorn app.main:app` 代替（仓库里的两个 bat 已经是这么写的），或把项目放到纯英文路径。

## 开发

```bash
make test    # 离线跑，全部用假响应，不联网
```

想参与改进直接开 Pull Request，不用先问；遇到问题欢迎提 [Issue](../../issues)。

## 开源协议

[MIT](LICENSE) © 2026 Eiko
