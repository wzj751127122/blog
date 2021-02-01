---
title: 今天你的Kubernetes集群崩了吗3-cgroups溢出
date: 2020-05-25
updated: 2020-05-25
categories:
  - Record
tags:
  - Kubernetes
  - Crash
  - Linux Kernel
---

> 本问题只会在 K8s1.8 版本以上和较低的内核版本的场景中出现，不过目前已知在 4.4 中依旧会出现。如果还在用较低版本内核的同志们就需要注意一下这个问题了。内核版本高的可以忽略了。

## 背景

有阵子发现很多 worker 节点用着用着就会提示剩余空间不足的错误，具体如下所示：

```bash
mkdir /sys/fs/cgroups/memory/docker/406cf...1eb13a: no space left on device
```

可实际上通过`df`命令查看硬盘使用情况的时候却发现这个目录所在的分区可能实际使用量很小。经过一段时间的排查后发现这其实是一个内核问题，而且是一个潜在的“定时炸弹”。

## Docker 虚拟化原理

Docker 是一个轻量级的虚拟化技术，与传统虚拟化计数不同， Docker 并非是建立于 Hypervisor 之上的虚拟机应用。通过下图我们可以看到 Docker 和基于 Hypervisor 的虚拟机技术之间的区别：

![Docker 工作原理](/images/docker工作原理.png)

在上图中我们可以看到，Docker 容器在运行时并不会带入一个新的操作系统，换句话说 Docker 容器其实就是一个带有特殊视角的普通进程。但既然容器只是一个普通进程，那么为什么容器并不能直接访问到宿主机上的资源呢？而且通过设置，容器也不能无限制的使用宿主机的资源。为了实现容器计算资源和进程工作区的隔离， Docker 使用了 Namespace 和 Cgroups 这两项技术。

### 资源隔离

Namespace 和 Cgroups 都是 Linux 内核中的特性。

**Namespace**: 通过 Namespace，我们可以对进程提供内核资源上的隔离，即进程、网络、用户、UTS 等多种资源的隔离。Docker 使用了其中以下几种 Namespace 进行隔离:

- pid: 用以进程隔离
- net: 用以网络隔离
- ipc: 用以 IPC(进程间通信)隔离
- mnt: 用以挂载点(文件)隔离
- UTS: 用以内核版本，主机名，域名隔离

简单来说，有了 Namespace，我们就不需要担心容器会访问到不该访问的资源。

**cgroups**: 即 Linux Control Group。这项技术主要用来限制物理资源的使用上限，如 CPU、内存、磁盘和带宽等。Docker 通常会通过 Cgroups 来实现 CPU 和内存的限制。

## 故障成因

本次故障就是由于 Cgroups 的 BUG 所导致的。当我们为工作负载设置内存限制时，Docker_HOST 会在`/sys/fs/cgroups/memory/docker/`目录下为容器创建对应的目录，并在其中设置内存的使用上限。

而 Memcg 是 Linux 中用来管理 Cgroups 内存的模块。在 Memcg 中默认会开启 Kmem(Kernel memory accounting) 功能，这个功能可以在设置 Cgroups 限制应用对用户内存的使用后再继续增加应用对内核内存的使用限制 [1]。由于内核内存并不能使用 swap，这意味着内核内存是一个非常有限的资源，所以开启 Kmem 后内核会限制 memcg struct 的数量。通常情况下，伴随着 Pod 的漂移或新建销毁过程中 Cgroups 的消亡，相应的 memcg struct 也应该随即释放，但是该对象只会在出现内存压力时被回收[2]。就这样 memcg struct 的数量不断上升，这个 struct 中的 id 值也不断的接近设定的临界值。

在内核内存中 memcg struct 的 id 到达 65535 临界值后，虽然可能实际上只有三五个 Pod 在运行，内核仍然会拒绝后续带有资源限制容器部署创建 Cgroups 的行为，最终导致前文中错误日志产生。在后续的内核更新( [73f576c04](https://github.com/torvalds/linux/commit/73f576c04b9410ed19660f74f97521bee6e1c546) )中 memcg id 和 memcg struct 得到了分离，其 id 能够在 Cgroups 销毁后被释放。[3]

当我们启用了弹性伸缩、CICD、Cronjob 等自动化的 Pod 创建任务或者某些容器因为存在故障而不断 crash backoff 时，Pod 的反复创建会加快 id 到达临界值的速度。即使没有上述情况，也有可能会在未来的某一个时间点中触发该故障。

如果在系统日志中发现类似前文中的日志产生，但是通过`sudo cat /proc/cgroups |grep memory`却发现**num_groups**（即输出内容的第三项）并没有达到临界值，就可以确认是本文中提到的问题了。

## 处理方法

处理本类故障主要有三类方式，分别是**安装更新**、**释放内存**和**禁用 Kmem 功能**。在下文中会列出这几类处理方式的多种实践方式及其优劣，在实际遇到相关问题时可以依据实际情况结合一种或多种实践方式来执行。

1. **安装更新**：通过以下其中一种方式安装更新可以一劳永逸的避免该类问题的复现。

   - 升级内核版本到包含 commit hash 为 [73f576c04](https://github.com/torvalds/linux/commit/73f576c04b9410ed19660f74f97521bee6e1c546) 的 4.6.7 及更高版本
   - 安装 [RHSA-2019:3055](https://access.redhat.com/errata/RHSA-2019:3055) 补丁
   - 升级 RHEL 到不久前发布的 7.8

   这种方式可以从源头上阻止问题的复现，但很多情况下我们并不能随意的去升级运行中的节点的内核、安装安全补丁之类的，因为这会导致机器重新启动，并带来未知的新问题。

2. **重置计数**：通过以下其中一种做法，我们可以释放掉内存中已有的 struct 来临时恢复节点的可用性。

   - 重启节点
   - 设置一个定时任务`6 */12 * * * root echo 3 > /proc/sys/vm/drop_caches`，定期将释放计数。

   这两种做法都是仅适用于紧急情况的临时处理方法。用户需要慎重考虑这些操作会带来的副作用：前者可能会导致 Pod 漂移等意外结果，后者会影响性能并可能导致一些状态为 `dangling` 的容器 Cgroups 被释放。同时后者也无法应对发生由于容器运行错误导致的突发性溢出问题，无法作为正式的处理方案。优点就是见效快，能够在短期内处理问题。

3. **禁用功能**：通过以下其中一种做法，我们可以暂停使用 Kmem 功能。禁用该功能后，将不再会有对内核内存的限制，自然也就没有了临界值的限制。

   - 将内核参数设置为`cgroup.memory=nokmem`
   - 重新编译 Kubelet 来禁止使用相关特性。以 1.14.1 版本为例，其编译命令如下：：

     ```bash
     $ git clone --branch v1.14.1 --single-branch --depth 1 [https://github.com/kubernetes/kubernetes](https://github.com/kubernetes/kubernetes)
     $ cd kubernetes

     $ KUBE_GIT_VERSION=v1.14.1 ./build/run.sh make kubelet GOFLAGS="-tags=nokmem"
     ```

     编译完成后，更新将 Kubernetes 集群中的组件更新为新编译的版本。

   在无法对系统进行更新的情况下可以采取这种方式。云昊容器云团队最后所采用的处理方法是通过重新编译 Kubelet，这样我们就可以在不重启机器的情况下处理并避免该问题的再次发生。

## 参考资料

- https://lkml.org/lkml/2016/7/13/587
- https://github.com/kubernetes/kubernetes/issues/61937
- https://github.com/kubernetes/kubernetes/issues/70324
- https://lore.kernel.org/patchwork/patch/690171/
- https://docs.docker.com/get-started/overview/#the-underlying-technology
