Punctuator

**还不到。**

我知道很多教程讲完 StateStore 就开始讲 `Punctuator`，但是**按照你这个项目的复杂度，我会故意晚一点引入它**。

原因是要先弄清楚**谁触发检查（Trigger）**。

------

# Kafka Streams 有两种触发方式

## 第一种：事件驱动（Event Driven）

收到一条新的 Kafka 消息，就执行一次。

例如：

```text
ORDER_HEADER Topic

1001
1002
1003
```

每收到一条：

```text
process()

↓

更新 StateStore

↓

检查 Marker
```

你的 `ProgressProcessor` 现在就是这种。

------

## 第二种：时间驱动（Time Driven）

不是收到消息。

而是：

```text
30 秒

↓

执行一次
```

例如：

```java
context.schedule(
    Duration.ofSeconds(30),
    PunctuationType.WALL_CLOCK_TIME,
    ...
);
```

这就是 Punctuator。

------

# 你的项目到底什么时候需要 Punctuator？

我们看整个流程。

## 情况一：业务 CDC 一直在流

```text
Marker

↓

1005
```

业务：

```text
1001

1002

1003

1004

1005
```

每来一条：

ProgressProcessor：

```text
update()

↓

check()
```

最后：

1005：

来了。

READY。

**这里根本不需要 Punctuator。**

------

## 情况二：CDC 卡住了

例如：

```text
Marker

1005
```

但是：

```text
ORDER

1003
```

然后：

再也没有：

新消息。

如果：

没有：

Punctuator。

永远：

不会：

有人：

检查。

Marker：

一直：

WAITING。

------

所以：

Punctuator：

负责：

```text
WAITING

↓

超过30分钟

↓

TIMEOUT
```

而不是：

READY。

------

# 我会这样设计

真正判断：

READY：

还是：

事件驱动。

```text
Business CDC

↓

ProgressProcessor

↓

Coordinator.check()
```

Punctuator：

只负责：

```text
每30秒

↓

扫描 WAITING Marker

↓

是否超时？
```

或者：

```text
CDC Lag

恢复了吗？
```

------

# 还有一个作用

比如：

Kafka：

今天：

凌晨：

没有：

任何：

消息。

Marker：

已经：

READY。

但是：

因为：

没有：

新 CDC。

没人：

触发：

Coordinator。

Punctuator：

可以：

补一刀。

```text
每30秒

↓

checkWaitingMarker()
```

所以：

它：

更像：

保险。

------

# 为什么我一直没让你写 Punctuator？

因为：

Coordinator：

应该：

先写好。

例如：

```java
public SnapshotAudit check(Checkpoint checkpoint)
```

这就是：

**唯一的判断逻辑。**

然后：

两种地方：

调用：

它。

------

## 第一种

ProgressProcessor

```java
process()

↓

Coordinator.check()
```

------

## 第二种

Punctuator

```java
schedule()

↓

Coordinator.check()
```

注意：

**完全复用同一个方法。**

而不是：

写两套判断。

------

# 最终结构

```text
                 ProgressProcessor
                        │
                        │
                        ▼
                 SnapshotCoordinator
                        ▲
                        │
                        │
                  Punctuator
```

所以：

Coordinator：

才是真正：

Brain。

Processor：

只是：

事件：

入口。

Punctuator：

只是：

时间：

入口。

------

# 我的经验（也是很多 Streams 项目的做法）

很多人会把判断逻辑直接写在：

```java
process(...)
```

或者：

```java
punctuate(...)
```

最后：

两份：

代码。

维护：

非常：

痛苦。

我一般：

都会：

抽成：

```java
SnapshotCoordinator
```

任何地方：

都：

调用：

它。

------

## 所以我们的下一步应该是：

**先完成 `SnapshotCoordinator.check()` 的完整实现，再加 `Punctuator`。**

因为 `Punctuator` 本身其实只有十几行代码，它真正有价值的地方不是定时器，而是**定时去调用已经写好的 Coordinator**。

这样代码职责会非常清晰：

- **ProgressProcessor**：更新 `TopicProgressStore`，然后调用 `coordinator.checkWaitingMarkers()`
- **MarkerProcessor**：更新 `CheckpointStore`，不做判断
- **SnapshotCoordinator**：唯一负责 READY/FAILED 的业务规则
- **Punctuator**：定时调用 `coordinator.checkWaitingMarkers()`，处理长时间无新消息、超时等场景

这种职责划分也是企业项目里最容易测试和维护的设计。