下一步好，现在开始就真正进入**企业级架构**了。

其实到这里，你会发现，我已经**不是按照 Kafka Streams 教程在讲了**，而是在按照 **DDD（领域驱动设计）+ Kafka Streams** 的方式设计。

这是很多大型项目（银行、证券、物流）常见的做法。

------

# 我们先看现在的问题

目前 ProgressProcessor 是这样的：

```java
public void process(...) {

    // 更新 StateStore

    store.put(...);

    // 然后判断

    coordinator.check(...);
}
```

问题来了。

Coordinator 需要的数据很多：

```text
CheckpointStore

TopicProgressStore

JobDefinition

Lag

......
```

如果都在 Processor 里取：

```java
store1.get()

store2.get()

store3.get()
```

Processor 就会越来越胖。

以后：

500 行。

------

## 所以需要一层 Service

架构变成：

```text
ProgressProcessor
        │
        ▼
CheckpointService
        │
        ▼
SnapshotCoordinator
```

Processor：

以后：

只负责：

```text
收到 Kafka Message
```

剩下：

全部：

交给：

Service。

------

# 第一部分

CheckpointService

接口：

```java
public interface CheckpointService {

    void updateTopicProgress(
            String topic,
            CdcMessage message);

    void receiveCheckpoint(
            Checkpoint checkpoint);

}
```

为什么：

没有：

```java
check()
```

因为：

Service：

应该：

自动：

决定。

例如：

收到：

CDC。

自动：

检查。

收到：

Marker。

自动：

保存。

------

# 实现

```java
public class DefaultCheckpointService
implements CheckpointService {

    private TopicProgressRepository progressRepository;

    private CheckpointRepository checkpointRepository;

    private SnapshotCoordinator coordinator;

}
```

注意。

这里：

已经：

没有：

Kafka Streams。

只有：

Repository。

------

# Repository

很多人第一次学 Streams 都直接：

```java
store.get(...)
```

其实：

最好：

封装。

例如：

```java
public interface TopicProgressRepository {

    void save(TopicProgress progress);

    TopicProgress find(String topic);

    List<TopicProgress> findAll();

}
```

实现：

```java
public class StreamsTopicProgressRepository
implements TopicProgressRepository {

    private KeyValueStore<String,TopicProgress> store;

}
```

以后：

如果：

不用：

Kafka。

改：

JPA。

Coordinator：

不用：

改。

------

Checkpoint：

也是。

```java
public interface CheckpointRepository {

    void save(Checkpoint checkpoint);

    List<Checkpoint> waiting();

}
```

------

# ProgressProcessor

终于：

变得：

特别：

简单。

```java
public void process(
        Record<String,CdcMessage> record){

    service.updateTopicProgress(

            topic,

            record.value()

    );

}
```

只有：

一句。

------

MarkerProcessor：

也是。

```java
public void process(...){

    service.receiveCheckpoint(

            checkpoint

    );

}
```

------

# Service 内部

真正：

发生：

事情。

```java
public void updateTopicProgress(...) {

    repository.save(progress);

    checkWaitingCheckpoint();

}
```

看到没有？

Processor：

不知道：

Coordinator。

Processor：

不知道：

Checkpoint。

Processor：

不知道：

StateStore。

全部：

隐藏。

------

# checkWaitingCheckpoint()

这里：

就是：

真正：

Brain。

例如：

```java
private void checkWaitingCheckpoint(){

    List<Checkpoint> checkpoints =

            checkpointRepository.waiting();

    for(Checkpoint cp : checkpoints){

        SnapshotAudit audit =

                coordinator.check(cp);

        if(audit.isReady()){

            publish(audit);

        }

    }

}
```

------

# 这里又有一个性能问题

如果：

一天：

1000 个：

Checkpoint。

每：

CDC：

都：

循环：

1000 次。

还是：

不好。

所以：

下一步：

继续：

优化。

------

# PendingCheckpointQueue

不要：

```java
List
```

改：

PriorityQueue。

按照：

```text
WatermarkSequence
```

排序。

例如：

```text
1005

↓

JOB1
1400

↓

JOB2
1800

↓

JOB3
```

永远：

检查：

最小：

那个。

```java
Checkpoint cp =

queue.peek();
```

如果：

JOB1：

还：

没：

READY。

直接：

结束。

不用：

检查：

JOB2。

------

# 最终架构

```text
                    Kafka Streams
                          │
          ┌───────────────┴──────────────┐
          │                              │
          ▼                              ▼
 ProgressProcessor              MarkerProcessor
          │                              │
          └───────────────┬──────────────┘
                          ▼
                 CheckpointService
                          │
        ┌─────────────────┼──────────────────┐
        ▼                 ▼                  ▼
 TopicProgressRepo   CheckpointRepo    JobDefinitionRepo
        │                 │                  │
        └─────────────────┼──────────────────┘
                          ▼
                SnapshotCoordinator
                          │
                          ▼
                  SnapshotAudit
                          │
                          ▼
              snapshot-audit-topic
```

------

# 现在可以开始 Punctuator 了吗？

**可以了，而且现在才是最佳时机。**

原因是现在已经有了：

- `CheckpointService`
- `SnapshotCoordinator`
- `Repository`

所以 Punctuator 根本不用知道任何业务细节，只需要：

```java
context.schedule(
    Duration.ofSeconds(30),
    PunctuationType.WALL_CLOCK_TIME,
    timestamp -> checkpointService.checkWaitingCheckpoints()
);
```

注意这一点非常重要：

- **ProgressProcessor** 调用 `checkpointService.checkWaitingCheckpoints()`
- **Punctuator** 也调用 `checkpointService.checkWaitingCheckpoints()`

它们共用**同一套业务逻辑**，这也是企业项目里最推荐的设计方式。

------

## 我建议下一节就正式讲 **Punctuator**。

这一节不仅会讲 `context.schedule(...)` 怎么用，还会讲：

1. `STREAM_TIME` 和 `WALL_CLOCK_TIME` 的区别（这是 Kafka Streams 面试高频题）。
2. 为什么你的 CDC 项目必须选择 `WALL_CLOCK_TIME`。
3. 如何利用 Punctuator 实现 **WAITING → TIMEOUT**。
4. 如何实现 **无新 CDC 消息时仍能完成 READY 判断**。

这也是 Kafka Streams 真正开始体现"流处理框架"能力的地方。