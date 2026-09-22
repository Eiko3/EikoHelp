# EikoHelp — 电商智能客服 Agent

《AI Agent 智能客服实战》的配套源码。一个能查订单物流、答政策 FAQ、走退款子流程、
挖知识补库、还能微调一个主题分类器的完整客服系统。

代码是随课程一章章长出来的，不分支：ch01 一个纯对话接口起步，到 ch10 收尾时是下面这套东西。

## 技术栈

FastAPI + LangGraph / LangChain + SQLAlchemy / MySQL + Milvus。

聊天、嵌入、重排三组上游各自直连，没有网关那一层。模型名和地址都在 `.env` 里配
(`CHAT_*` / `EMBED_*` / `RERANK_*` 三组)，换供应商、换模型不用改代码。

## 环境要求

| 项 | 要求 |
| - | - |
| uv | 包管理与 Python 运行时管理（Python 版本不用自己装，uv 会拉） |
| Docker | 跑 MySQL / Milvus / MinIO / etcd 四个依赖容器 |
| 内存 / 磁盘 | 8G 内存起步，10G 空闲磁盘（含 Docker 镜像） |
| 模型密钥 | 一家 OpenAI 兼容上游的 API Key（默认配置按硅基流动给的，注册一个账号即可跑通全部章节） |

## 跑起来

```bash
cp .env.example .env      # 填 CHAT_* / EMBED_* / RERANK_* 三组密钥
uv sync                   # 装依赖
docker compose up -d      # MySQL / Milvus / MinIO / etcd（首次启动自动建表+灌种子数据）
make kb-build             # 知识库切块落 MySQL
make kb-vectorize         # 向量化写进 Milvus（会调嵌入接口）
make dev                  # 依赖容器 + MCP :8101/:8102 + 应用 :8000
```

浏览器打开 <http://localhost:8000> 就是聊天页。

**Windows 图省事**：仓库根目录有两个双击即用的启动器——`启动EikoHelp.bat` 起服务并打开
聊天页，`打开后台管理.bat` 打开后台管理页（服务已在跑时不会重复起进程）。它们只是把上面
的 `make dev` 最短路径包了一层，Linux / macOS 用 Makefile 即可。

### 两种部署姿势

- **自己动手**：上面的命令就是最短路径，每步的验收标准、常见坑（镜像拉不动、端口冲突、
  密钥填错的症状）都写在 [`DEPLOY.md`](DEPLOY.md)。
- **丢给 AI 编程助手**：把 [`DEPLOY.md`](DEPLOY.md) 交给 Claude Code、Cursor 之类的工具，
  说一句「按 DEPLOY.md 把项目部署起来」，它会自己走完全部步骤并自验收。

### 验收装好了没有

```bash
printf '{"user_id":"u1","message":"订单 1001 的物流到哪了"}' > /tmp/q.json
curl -s --max-time 90 http://localhost:8000/api/agent \
     -H 'Content-Type: application/json' --data-binary @/tmp/q.json
```

返回 JSON 的 `tool_calls` 里出现 `query_order` 和 `query_logistics`、`answer` 里有物流状态，
就是部署成功了。

## 代码怎么组织

| 位置 | 装的是什么 |
| - | - |
| `app/api/` | HTTP 入口。聊天、Agent、知识库录入、复核、验收页、成本看板 |
| `app/graph/` | LangGraph 那张图。`state` 状态、`nodes` 节点、`routing` 分流规则、`build` 组装 |
| `app/core/` | 单点能力。上游客户端、检索、重排、意图、指代、摘要、置信度、飞轮、可观测 |
| `app/kb/` | 知识怎么进库。切块、嵌入、双写 MySQL 与 Milvus、去重、从对话里挖问答对 |
| `app/tools/` | 工具系统。内置 `@tool`、MCP 客户端、注册表、统一执行引擎 |
| `app/db/` | 表模型与仓储 |
| `app/static/` | 前端页面。聊天、知识库录入、飞轮待审、观测与成本、主题分布、分类器验收 |
| `mcp_servers/` | 两台业务 MCP Server，物流和售后各一台，独立进程 |
| `sql/` | 各章的建表与迁移，容器首启按文件名顺序自动执行 |
| `scripts/` | 建库、评估、微调这些离线活 |
| `docs/superpowers/` | 各章的 spec 和 plan。课程实战篇教的就是这套流程，留着当范本 |

## 各章长出了什么，怎么验

`make test` 跑全部单测，不打真实模型。下面这些要真服务在跑。

| 章 | 这一章长出来的东西 | 验收 |
| - | - | - |
| ch01 | 流式对话、结构化提取 | `make eval` |
| ch02 | 五个 `@tool` 业务工具，单轮 Function Calling | `make eval-agent` |
| ch03 | 切块、嵌入、MySQL 与 Milvus 双写、对话挖知识 | `make kb-build` `make kb-vectorize` `make eval-retrieval` |
| ch04 | 混合检索、RRF、重排、Query 改写、四策略评估 | `make smoke-rag` `make eval-rag` |
| ch05 | LangGraph workflow 骨架 + 主力 Agent 的 ReAct 环 | `make eval-ch05` |
| ch06 | 分流器、指代消解、退款子流程的 interrupt/resume | `make smoke-interrupt` `make eval-ch06` |
| ch07 | 上下文管理。滑窗、摘要、前缀缓存 | `make eval-ch07` |
| ch08 | 工具系统。MCP 动态发现、统一执行引擎、审计日志 | `make eval-ch08` |
| ch09 | Langfuse 自部署、数据飞轮、成本账 | `make langfuse-up` `make flywheel` `make eval-flywheel` `make cost-report` |
| ch10 | 主题分类器。语料、微调、阈值扫描、ONNX 推理服务 | `make ch10-corpus` `make ch10-train` `make ch10-eval` |

每条验收命令的前置条件（哪些服务得先起、哪张表得先建）用 `make help` 看，每个目标
都带了说明；部署层面的前置条件在 [`DEPLOY.md`](DEPLOY.md)。

## 端口与页面

| 端口 | 是什么 |
| - | - |
| 8000 | 应用 |
| 8101 / 8102 | 业务 MCP Server，物流 / 售后 |
| 8110 | ch10 主题分类器推理服务（`make classifier-up` 之后） |
| 3000 | Langfuse（`make langfuse-up` 之后） |
| 19530 | Milvus |

应用页面：`/` 聊天、`/admin` 后台管理、`/kb` 知识库录入、`/review` 飞轮待审、
`/observability` 观测与成本、`/topics` 主题分布、`/acceptance` 分类器验收。

## 参与贡献

发现问题欢迎提 [Issue](../../issues)；修 Bug、补文档直接开 Pull Request 就行，
不用先问。开发环境就是上面的「跑起来」那一套，提 PR 前跑一下 `make test`。

## License

[MIT](LICENSE)
