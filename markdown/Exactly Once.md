好，我们继续。

接下来就是 **Exactly Once（EOS）**。这是 Kafka Streams 企业项目里最重要的特性之一，也是很多人容易误解的地方。

不过在讲 API 之前，我们先回到**你的项目**。

------

# 如果没有 EOS，会发生什么？

假设：

```text
ORDER_HEADER

1004
```

更新了：

```text
TopicProgressStore

↓

1004
```

Coordinator 判断：

```text
READY
```

于是：

发送：

```text
snapshot-audit-topic
```

结果：

**发送成功以后，程序突然崩了。**

例如：

```text
ProgressProcessor
        │
        ▼
StateStore 已更新 ✔
        │
        ▼
Audit Topic 已发送 ✔
        │
        ▼
应用崩溃
        │
        ▼
Offset 还没提交 ✘
```

------

## 应用重启

Kafka 认为：

```text
这条 CDC 没处理完
```

于是：

再次消费：

```text
ORDER_HEADER

1004
```

Coordinator：

再次：

判断：

```text
READY
```

再次：

发送：

```text
snapshot-audit-topic
```

最后：

Audit：

变成：

```text
JOB1 READY

JOB1 READY
```

两条。

领导：

看：

日报。

懵了。

------

# 为什么会这样？

因为：

正常：

Kafka：

有：

三个：

动作。

```text
消费 Message

↓

更新 StateStore

↓

发送 Audit

↓

提交 Offset
```

如果：

中间：

崩了。

这些：

不是：

一个：

事务。

------

# EOS 干了什么？

Kafka Streams：

把：

下面：

三个：

动作。

变成：

一个：

事务。

```text
消费

+

StateStore

+

Producer

+

Commit Offset
```

全部：

成功。

才：

真正：

提交。

------

例如：

```text
BEGIN TRANSACTION

↓

更新 StateStore

↓

发送 snapshot-audit-topic

↓

Commit Offset

↓

COMMIT
```

任何：

一步：

失败。

整个：

事务：

回滚。

------

# 配置

实际上：

只需要：

一行。

```properties
processing.guarantee=exactly_once_v2
```

还有：

```properties
replication.factor=3
```

生产：

推荐。

------

# Streams 自动做什么？

你：

完全：

不用：

写：

```java
beginTransaction()

commit()
```

Streams：

全部：

自动。

------

例如：

你的：

Processor：

还是：

```java
context.forward(auditRecord);
```

不用：

改。

------

# StateStore 也有事务吗？

很多人不知道。

答案：

**有。**

例如：

```text
TopicProgressStore

↓

1004
```

如果：

事务：

失败。

恢复：

以后：

还是：

```text
1003
```

不会：

出现：

```text
Store 更新了

Audit 没发
```

这种：

不一致。

------

# 放到你的项目

整个：

事务：

就是：

```text
收到 CDC

↓

更新 TopicProgressStore

↓

Coordinator

↓

发送 snapshot-audit-topic

↓

提交 Offset
```

要么：

全部：

成功。

要么：

全部：

失败。

------

# 那 PostgreSQL 呢？

这里：

很多人：

第一次：

会：

问。

你的：

架构：

是：

```text
IBM i

↓

Kafka

↓

Kafka Streams

↓

snapshot-audit-topic

↓

Kafka Connect Sink

↓

PostgreSQL
```

注意。

EOS：

只保证：

```text
Kafka 内部
```

例如：

```text
Streams

↓

Topic
```

不能：

保证：

```text
Topic

↓

PostgreSQL
```

------

所以：

Sink：

也：

要：

支持：

幂等。

例如：

```sql
checkpoint_id
```

做：

唯一键。

```sql
PRIMARY KEY
```

这样：

重复：

READY：

不会：

插：

两次。

------

# 真正企业怎么做？

例如：

```sql
checkpoint_id
```

唯一。

然后：

```sql
INSERT ...

ON CONFLICT

DO UPDATE
```

或者：

```sql
MERGE
```

这样：

即使：

Kafka：

重放。

数据库：

也是：

安全。

------

# 你的 Audit 表

我建议：

主键：

就是：

```text
checkpoint_id
```

例如：

```sql
CREATE TABLE snapshot_audit(

    checkpoint_id varchar(100)
        PRIMARY KEY,

    batch_id varchar(50),

    ready boolean,

    report jsonb
);
```

这样：

JOB1：

永远：

只有：

一条。

------

# 那还有必要 EOS 吗？

有！

因为：

EOS：

解决的是：

**Kafka 内部状态一致性**。

数据库：

唯一键：

解决的是：

**外部系统幂等性**。

两者：

不是：

替代关系。

而是：

叠加。

------

# 到这里，你这个项目已经有了：

```text
Processor API      ✅
StateStore         ✅
Coordinator        ✅
Punctuator         ✅
Exactly Once       ✅
```

还剩最后一个核心能力：

## **GlobalKTable**

这一部分其实会直接解决你之前提过的问题：

> **如果以后一个 Batch 增加业务表，不想改 YAML、不想重启怎么办？**

GlobalKTable 就是 Kafka Streams 给这种**动态配置**准备的能力，也是很多生产系统用来管理业务规则、路由规则、Job 配置的方式。它会让你的 `JobDefinition` 从静态文件升级为**实时可更新的配置流**。