---
title: 今天你的Kubernetes集群崩了吗：Pod无限调度
date: 2020-05-14
updated: 2020-05-14
categories:
  - Record
tags:
  - Kubernetes
  - Crash
  - Etcd
---

前几天中午正吃着火锅唱着歌，手机上突然就弹出了大量的告警信息，汇报着某个 K8s 集群的 api-server 无法连接。经过一番检查，发现是集群中存在大量重复的 Pod 对象，这些对象使得 etcd 和 apiserver 占用了非常多的内存，且陷入了不可用的状态。为什么会这样呢？接下来和小编一起来看看吧。

## 万恶之源

众所周知，Kubernetes 是一个容器编排系统，它会将集群中各类应用的状态维持到声明中所要求的状态。为了能够更加精确的将集群维护到维护者想象中的状态，在 Kubernetes 中有着大量的机制来控制集群。而导致本次故障的，就是以下三个特性的不正确使用所导致的。

### [复制集](https://Kubernetes.io/docs/concepts/workloads/controllers/replicaset/)

其中，`Replicaset`是一种用来维护工作负载中 Pod 数量的控制器。当你在无状态工作负载中声明了`spec.replicas`字段，Kubernetes 就会将不断创建 Pod，直到可用 Pod 的数量满足声明后才会停止调度。

### [污点和容忍度](https://Kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

在创建 Pod 时，Kubernetes 需要将这个 Pod 的容器部署到某一个可用的节点上，这时候调度器就会选择出一个可用的节点，并将这个 Pod 部署到该节点上。

如果我们希望某些节点上面不会调度 Pod 上去，我们可以为该节点设置污点。这样一来，该节点就会拒绝未来新调度过来的 Pod(NoSchedule)，甚至驱散当前已有的 Pod(NoExecute)。只有配置了相应容忍度的 Pod 才可以继续被调度和运行到带有污点的节点上。

### [节点选择](https://Kubernetes.io/docs/concepts/scheduling-eviction/assign-Pod-node/)

而我们又可以通过声明(`nodeName`)来将一些 Pod 调度到指定的节点上。这些 Pod 将不会部署在其他名称的节点上。

### 悲剧发生

现在，让我们想象一下，当一个带有复制集的工作负载设置了节点选择器后，他所选择的节点突然被打上了`NoExecute`污点。但是工作负载中并没有设置相应的容忍度。这时候会发生什么情况呢？

- A. 工作负载停止创建 Pod，并提示所选节点带有污点
- B. Pod 部署失败，提示无法部署后以`unavalible`的状态终止部署
- C. Pod 部署失败，删除当前 Pod 继续部署
- D. Pod 部署失败，立刻创建新对象继续尝试部署

很显然，答案是最不显然的 D。污点的实现是在调度时去判断当前节点是否带有污点，及是否符合要求，如果没有符合需求的节点，这个 Pod 的部署就会阻塞住。而声明了`nodeName`，Pod 的部署会跳过节点的选择，直接部署到目标节点，然后该 Pod 就会被因为没有对应容忍度被拒绝，并标注其状态为`Evicted`。

由于这次失败并非是容器运行的失败，Kubernetes 的控制器会尝试继续创建 Pod，使得可用的 Pod 数量与复制集中声明的数量一致。而这个过程非常的迅速，一瞬间就能创建出无数个 Pod，并且随着时间的不断的扩充着 Pod 的规模。直至集群中的 master 节点崩溃。

## 处理方法

很幸运的是，我们在集群还没有完全崩溃之前发现了这个问题。不过虽然集群还没崩溃，但是 apiserver 的响应时间已经变得非常的长了，随便一个 get 请求都可能需要等 5 秒以上。随即我们通过 Kubectl 删除了全部相应的 Pod 和工作负载后，故障得到了解决。

我们可以通过以下命令来删除全部被驱散的 Pod

`kubectl -n kube-system get Pods | grep Evicted |awk '{print$1}'|xargs kubectl -n kube-system delete Pods`

如果真的是集群彻底崩溃，那么可能就会需要先停止 Kubernetes 相关组件的运行，并在 etcd 中手动删除相应的对象。然后再重新启用 k8s 组件。

## 总结
虽然表面上看，这种错误属于人为的操作失误，但是在实际情况中，k8s也会自动的为某些节点加上污点。如此一来，相似的情况就可能还会发生。

从源头上，我们可以尽可能的用节点选择器(nodeSelector)和节点亲和性(nodeAffinity)来调度Pod。通过这种方式部署的Pod会在调度之前进行一次验证，如果不存在可用的节点，调度就会停止。

或者可以通过[PDB](https://Kubernetes.io/zh/docs/concepts/workloads/Pods/disruptions/)来阻止创建过多的Pod。PDB可以控制应用在短时间因为非自愿干扰而关闭的Pod数量，进而可以避免无数个Pod被创建又驱散导致的集群崩溃。