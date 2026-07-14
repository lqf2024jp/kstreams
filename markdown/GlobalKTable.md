好，最后一个核心知识点：**GlobalKTable**。

这一章学完，你会发现我们设计的系统已经不像 Demo，而像真正的企业 CDC 平台。

------

# 一、为什么需要 GlobalKTable？

先回到你的项目。

目前我们一直写的是：

```yaml
jobs:
  JOB1:
    topics:
      - ORDER_HEADER
      - ORDER_DETAIL
      - CUSTOMER
```

Coordinator：

收到：

```text
JOB1
```

去：

YAML：

找：

```text
ORDER_HEADER

ORDER_DETAIL

CUSTOMER
```

问题来了。

领导：

下午：

突然：

说：

> 新增加一张表。

```text
ORDER_HISTORY
```

怎么办？

现在：

只能：

```text
修改 YAML

↓

重启 Kafka Streams
```

生产环境：

几乎没人愿意这样干。

------

# 企业怎么做？

把：

配置：

放到 Kafka。

例如：

建立：

```text
job-definition-topic
```

里面：

每一条：

就是：

一个 Job。

例如：

Key：

```text
JOB1
```

Value：

```json
{
  "jobId":"JOB1",

  "topics":[
      "ORDER_HEADER",
      "ORDER_DETAIL",
      "CUSTOMER"
  ]
}
```

然后：

JOB2

```json
{
  "jobId":"JOB2",
  "topics":[
      "PAYMENT",
      "PAYMENT_DETAIL"
  ]
}
```

------

# GlobalKTable 是什么？

很多人理解错。

它不是：

```text
Table
```

它其实是：

```text
每一个 Kafka Streams 实例

都保存

整个 Topic
```

例如：

Kafka：

```
job-definition-topic
```

里面：

```text
JOB1

JOB2

JOB3
```

那么：

每一个：

Streams：

节点。

都有：

```text
JOB1

JOB2

JOB3
```

一份。

所以：

叫：

Global。

------

普通：

KTable：

不是。

例如：

三个：

Streams：

实例。

KTable：

可能：

```text
机器A

JOB1
机器B

JOB2
机器C

JOB3
```

分区。

------

GlobalKTable：

永远：

```text
机器A

JOB1

JOB2

JOB3
机器B

JOB1

JOB2

JOB3
机器C

JOB1

JOB2

JOB3
```

全部。

------

# 为什么适合配置？

因为：

配置：

通常：

很小。

例如：

几十：

Job。

几百：

Topic。

几十 KB。

完全：

可以：

复制。

------

# 放到你的项目

以前：

Checkpoint：

来了。

```text
JOB1
```

Coordinator：

```java
jobDefinitionRepository.find("JOB1");
```

以后：

Repository：

不用：

YAML。

直接：

GlobalKTable。

例如：

```java
GlobalKTable<String,JobDefinition>
```

里面：

已经：

有：

```text
JOB1
```

直接：

返回。

------

# 如果新增业务表

例如：

运维：

发送：

一条：

Kafka：

Message。

Key：

```text
JOB1
```

Value：

```json
{
  "jobId":"JOB1",

  "topics":[
      "ORDER_HEADER",
      "ORDER_DETAIL",
      "CUSTOMER",
      "ORDER_HISTORY"
  ]
}
```

几秒钟：

以后。

所有：

Streams：

实例。

自动：

更新。

Coordinator：

下一次：

检查。

自动：

变成：

```text
ORDER_HEADER
ORDER_DETAIL
CUSTOMER
ORDER_HISTORY
```

完全：

不用：

重启。

------

# 代码

建立：

GlobalKTable。

```java
GlobalKTable<String,JobDefinition>

jobTable = builder.globalTable(
        "job-definition-topic"
);
```

以后：

Join。

例如：

Marker：

里面：

```text
JOB1
```

自动：

Join：

```text
JOB1
```

配置。

------

# 你的项目最终拓扑

```text
                IBM i

                  │

                  ▼

              CDC Topics
                  │
                  ▼
          ProgressProcessor
                  │
                  ▼
         TopicProgressStore

Marker Topic ───► MarkerProcessor
                  │
                  ▼
          CheckpointStore

Job Definition Topic
                  │
                  ▼
            GlobalKTable
                  │
                  ▼
         CheckpointService
                  │
                  ▼
       SnapshotCoordinator
                  │
                  ▼
        snapshot-audit-topic
                  │
                  ▼
             PostgreSQL
```

------

# 再往前一步（真正企业做法）

到这里，我还会继续升级。

JobDefinition 不只是：

```java
topics
```

而是：

```java
class JobDefinition {

    String jobId;

    List<String> topics;

    Duration timeout;

    boolean checkTimestamp;

    boolean checkSequence;

    boolean requireLagZero;

    String journalLibrary;

    String journalName;

}
```

这样：

不同 Job 可以有不同规则。

例如：

```text
JOB_ORDER

↓

timeout=30min
JOB_PAYMENT

↓

timeout=5min
```

甚至：

```text
JOB_REPORT

↓

不检查 Timestamp
```

Coordinator：

完全：

不用：

改代码。

------

# 到这里，你已经掌握了 Kafka Streams 最重要的五个能力

| 能力              | 在你的项目中的作用                              |
| ----------------- | ----------------------------------------------- |
| **Processor API** | 处理每条 CDC、Marker 消息                       |
| **StateStore**    | 保存 Topic 最新进度、Checkpoint                 |
| **Punctuator**    | 定时检查等待中的 Checkpoint、处理超时           |
| **Exactly Once**  | 保证 StateStore 和 Audit Topic 一致，不重复输出 |
| **GlobalKTable**  | 动态维护 JobDefinition，无需 YAML 和重启        |

------

## 我想给你一个建议

到这里，其实我们已经不是在"学 Kafka Streams"了。

我们已经设计出了一个完整的 **CDC Snapshot Coordinator**。如果继续完善，我建议把它做成一个真正可以运行的 Maven 项目，而不是继续停留在代码片段。

这个项目可以包含：

- 完整的包结构（processor、service、repository、coordinator、model）。
- 本地 Docker 环境（Kafka + PostgreSQL）。
- 模拟 CDC 数据和 Marker 数据。
- GlobalKTable 动态配置。
- StateStore 持久化（RocksDB）。
- 最终生成 `snapshot-audit-topic` 并落库 PostgreSQL。

这样你不仅能深入掌握 Kafka Streams，还能得到一个非常贴近 IBM i CDC 实际场景的项目，以后无论是工作还是分享，都比单独学习书里的例子更有价值。