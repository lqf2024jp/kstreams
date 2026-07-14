好，终于到 **Punctuator** 了。

这也是 Kafka Streams 和普通 Java 最大的区别之一。

------

# 一、为什么需要 Punctuator？

先回到你的项目。

假设：

```text
13:00:00

Marker

Sequence=1005
```

保存到：

```text
CheckpointStore

↓

WAITING
```

然后：

业务 CDC：

```text
1001

1002

1003
```

突然：

没有：

新消息了。

如果：

你的程序：

只有：

```java
process(...)
```

那么：

以后：

永远：

没人：

执行：

```java
coordinator.check()
```

Marker：

永远：

WAITING。

------

所以：

Kafka Streams：

提供：

```text
Punctuator
```

意思：

> **即使没有任何 Kafka Message，也可以定时执行代码。**

------

# 二、Java 定时器 vs Punctuator

普通 Java：

```java
ScheduledExecutorService
```

Kafka Streams：

```java
context.schedule(...)
```

为什么不用 Java Timer？

因为：

Streams：

需要：

知道：

当前：

Task。

当前：

StateStore。

当前：

事务。

所以：

必须：

用：

Streams：

自己的。

------

# 三、最简单的例子

例如：

每：

10 秒：

打印：

```java
public class ProgressProcessor
extends ContextualProcessor<String,CdcMessage,String,CdcMessage>{

    @Override
    public void init(
            ProcessorContext<String,CdcMessage> context){

        super.init(context);

        context.schedule(

                Duration.ofSeconds(10),

                PunctuationType.WALL_CLOCK_TIME,

                timestamp->{

                    System.out.println(

                            "Check : "+timestamp);

                }

        );

    }

}
```

启动：

以后：

控制台：

```text
Check : 1752300000000

Check : 1752300010000

Check : 1752300020000
```

即使：

Kafka：

没有：

消息。

仍然：

执行。

------

# 四、真正放到你的项目

不是：

打印。

而是：

```java
context.schedule(

        Duration.ofSeconds(30),

        PunctuationType.WALL_CLOCK_TIME,

        timestamp->{

            checkpointService

                    .checkWaitingCheckpoints();

        }

);
```

看到没有？

整个：

Punctuator：

只有：

一句：

真正：

业务。

```java
checkpointService.checkWaitingCheckpoints();
```

------

# 五、checkWaitingCheckpoints()

终于：

派上：

用场。

```java
public void checkWaitingCheckpoints(){

    List<Checkpoint> checkpoints =

            checkpointRepository.waiting();

    for(Checkpoint cp:checkpoints){

        SnapshotAudit audit=

                coordinator.check(cp);

        if(audit.isReady()){

            publish(audit);

        }

    }

}
```

所以：

Punctuator：

什么：

业务：

都：

不知道。

只是：

```text
30秒

↓

叫 Service 干活
```

------

# 六、为什么不用 process()？

因为：

process：

必须：

```text
收到 Kafka Message
```

才：

执行。

Punctuator：

不用。

------

# 七、STREAM_TIME 和 WALL_CLOCK_TIME

这是 Kafka Streams 最容易混淆的地方。

有两种：

```java
PunctuationType.STREAM_TIME
```

和：

```java
PunctuationType.WALL_CLOCK_TIME
```

------

## WALL_CLOCK_TIME

就是：

真实：

时间。

例如：

```text
13:00:00

↓

13:00:30

↓

13:01:00
```

即使：

Kafka：

没有：

消息。

仍然：

执行。

------

你的项目：

必须：

这个。

为什么？

因为：

```text
CDC

停止

↓

还要：

Timeout
```

------

## STREAM_TIME

完全：

不一样。

它：

不是：

真实：

时间。

而是：

Message：

里面：

的：

Timestamp。

例如：

Topic：

```text
13:00:00

13:00:05

13:00:08
```

Streams：

看到：

Timestamp：

推进。

才：

执行。

如果：

没有：

Message。

```text
STREAM_TIME

停止
```

不会：

执行。

------

# 举例

Topic：

今天：

停了。

```text
13:00

Message
```

以后：

一小时：

没有：

数据。

STREAM_TIME：

一直：

```text
13:00
```

不会：

变。

Punctuator：

不：

执行。

------

但是：

WALL_CLOCK：

```text
13:00

↓

13:01

↓

13:02

↓

13:03
```

一直：

执行。

------

# 所以你的项目

必须：

```java
PunctuationType.WALL_CLOCK_TIME
```

不能：

```java
STREAM_TIME
```

否则：

CDC：

停住。

永远：

TIMEOUT：

不了。

------

# 八、企业里面真正怎么写？

实际上：

不会：

30 秒：

扫描：

整个：

Store。

而是：

```text
CheckpointQueue

↓

peek()
```

例如：

```text
1005

↓

JOB1
```

检查：

是不是：

READY。

如果：

不是。

结束。

如果：

READY。

```text
poll()
```

检查：

下一个。

这样：

性能：

最好。

------

# 九、最终完整流程

```text
                Kafka Streams

                      │

         Business CDC arrives

                      │

                      ▼

             ProgressProcessor

                      │

       update TopicProgressStore

                      │

                      ▼

             CheckpointService

                      │

                      ▼

          SnapshotCoordinator

                      │

        READY ? -------- NO

          │

         YES

          │

          ▼

 snapshot-audit-topic


============================

每30秒

↓

Punctuator

↓

CheckpointService

↓

SnapshotCoordinator

↓

READY ?

↓

snapshot-audit-topic
```

------

## 到这里，你已经掌握了 Kafka Streams 中最核心的四个能力：

- **Processor API**：处理每一条 CDC 或 Marker 消息。
- **StateStore**：保存运行状态（`TopicProgress`、`Checkpoint`）。
- **Coordinator/Service 分层**：把业务算法与 Kafka Streams API 解耦，方便测试和扩展。
- **Punctuator**：在没有新消息时也能推进系统，例如处理超时或重新检查等待中的 Checkpoint。

剩下的两个重要主题就是：

1. **Exactly Once（EOS）** —— 保证 `snapshot-audit-topic` 不会因为应用重启或故障恢复而重复输出。
2. **GlobalKTable** —— 把 `JobDefinition` 从 YAML 升级为 Kafka 中的动态配置，让新增/修改 Batch 配置无需重启应用。

完成这两部分之后，你这个 **CDC Snapshot Coordinator** 就已经具备生产级 Kafka Streams 应用的大部分核心能力了。