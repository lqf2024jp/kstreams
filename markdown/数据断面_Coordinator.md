好，我们现在进入**整个项目最核心的一部分**。

这一部分不是 Kafka Streams，而是**业务算法**。

实际上，如果这一步设计好了，以后换成 Flink、Spring Boot、Akka，甚至普通 Java 程序，都不用改算法。

------

# 我们先确定一个原则

**Coordinator 不依赖 Kafka Streams API。**

也就是说：

```java
SnapshotCoordinator
```

不知道：

- Kafka
- Topic
- Processor
- Context
- StateStore

它只知道：

```java
Checkpoint

TopicProgress

JobDefinition
```

这样最好测试。

------

# 第一步：重新定义模型

## Checkpoint

```java
public class Checkpoint {

    private String checkpointId;

    private String batchId;

    private long watermarkSequence;

    private Instant watermarkTimestamp;

}
```

例如：

```
JOB1

↓

1005
```

------

## TopicProgress

```java
public class TopicProgress {

    private String topic;

    private long lastJournalSequence;

    private Instant lastJournalTimestamp;

}
```

例如：

```
ORDER_HEADER

↓

1004
```

------

## JobDefinition

告诉 Coordinator：

这个 Batch 要检查哪些 Topic。

```java
public class JobDefinition {

    private String batchId;

    private List<String> topics;

}
```

例如：

```
JOB1

↓

ORDER_HEADER

ORDER_DETAIL

CUSTOMER
```

------

# 第二步：Audit

Coordinator 最终输出：

不是：

```java
boolean
```

而是：

```java
SnapshotAudit
```

例如：

```java
public class SnapshotAudit {

    private String checkpointId;

    private boolean ready;

    private List<TopicAudit> topics =
            new ArrayList<>();

}
```

里面：每个 Topic：

都有：结果。

------

## TopicAudit

```java
public class TopicAudit {

    private String topic;

    private long lastSequence;

    private long watermarkSequence;

    private boolean sequencePass;

    private Instant lastTimestamp;

    private Instant watermarkTimestamp;

    private boolean timestampPass;

}
```

以后：

日报：

直接：

就是：

它。

------

# 第三步：Coordinator

终于：

开始。

接口：

```java
public class SnapshotCoordinator {

    public SnapshotAudit check(
            Checkpoint checkpoint,

            JobDefinition job,

            Map<String, TopicProgress> progresses) {

        ...
    }

}
```

注意：

这里只有：

Java。

没有：

Kafka。

------

# 第四步：算法

假设：

Checkpoint：

```
1005
```

Job：

```
JOB1

↓

ORDER

DETAIL

CUSTOMER
```

循环：

```java
for(String topic : job.getTopics()){

    ...
}
```

每个 Topic：

```java
TopicProgress progress =
        progresses.get(topic);
```

例如：

ORDER：

```
1004
```

然后：

比较：

```java
boolean sequencePass =
        progress.getLastJournalSequence()
        <=
        checkpoint.getWatermarkSequence();
```

Timestamp：

```java
boolean timestampPass =
        !progress.getLastJournalTimestamp()
                 .isAfter(
                     checkpoint.getWatermarkTimestamp());
```

然后：

生成：

```java
TopicAudit audit =
        new TopicAudit(...);
```

加入：

```java
SnapshotAudit
```

------

# 第五步：最后判断 READY

以前：

我们：

一直：

说：

READY。

现在：

终于：

有：

地方：

计算。

```java
boolean ready =

audit.getTopics()

     .stream()

     .allMatch(

        t ->

            t.isSequencePass()

            &&

            t.isTimestampPass()

     );
```

最后：

```java
audit.setReady(ready);
```

整个：

Coordinator：

结束。

------

# 举个完整例子

Checkpoint：

```
1005
13:00:03
```

TopicProgress：

| Topic    | Seq  | Timestamp |
| -------- | ---- | --------- |
| ORDER    | 1004 | 13:00:02  |
| DETAIL   | 1005 | 13:00:03  |
| CUSTOMER | 1003 | 13:00:01  |

Coordinator：

输出：

```json
{
  "checkpointId":"JOB1-20260712",

  "ready":true,

  "topics":[

    {
      "topic":"ORDER",

      "sequencePass":true,

      "timestampPass":true
    },

    {
      "topic":"DETAIL",

      "sequencePass":true,

      "timestampPass":true
    },

    {
      "topic":"CUSTOMER",

      "sequencePass":true,

      "timestampPass":true
    }

  ]
}
```

------

如果：

DETAIL：

变成：

```
1007
```

输出：

```json
{
  "topic":"DETAIL",

  "sequencePass":false
}
```

整个：

```
ready=false
```

------

# 然后 Processor 怎么调用？

例如：

ProgressProcessor：

更新完：

StateStore：

以后：

```java
SnapshotAudit audit =

coordinator.check(

    checkpoint,

    job,

    progresses
);
```

如果：

```java
audit.isReady()
```

那么：

```java
context.forward(

audit
);
```

发送：

```
snapshot-audit-topic
```

------

# 这里还有一个需要改进的地方（也是下一步）

你会发现：

```java
Map<String, TopicProgress> progresses
```

是传进来的。

那么：

谁去：

```java
store.get(...)
```

把所有 TopicProgress 都取出来？

Coordinator 不应该知道 StateStore。

所以我们还缺一层。

我一般会叫：

```text
CheckpointService
```

或者：

```text
CheckpointEvaluator
```

结构变成：

```text
ProgressProcessor
        │
        ▼
CheckpointService
        │
        ├── TopicProgressStore
        ├── CheckpointStore
        ├── JobDefinition
        ▼
SnapshotCoordinator
        │
        ▼
SnapshotAudit
```

这样 **Coordinator 永远只做算法**，而 **CheckpointService 负责访问 Kafka Streams 的 StateStore**。

------

**我建议下一步就加这一层（CheckpointService）**。这是很多企业项目都会采用的分层方式，它会让你的代码从"能跑"提升到"容易测试、容易扩展"。后面再加入 `Punctuator` 时，`Punctuator` 和 `ProgressProcessor` 都只需要调用同一个 `CheckpointService.checkWaitingCheckpoints()` 方法即可，无需重复任何判断逻辑。