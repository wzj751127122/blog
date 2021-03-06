---
title: 今天你的Kubernetes集群崩了吗2-双Master节点
date: 2021-01-15
updated: 2021-01-15
categories:
  - Record
index_img: /img/kubernetes.png
tags:
  - Kubernetes
  - Crash
  - Etcd
---

大家都知道，一个 Kubernetes 集群是由 Master 节点和 Worker 节点组成的。Master 节点中通常会包含各类[控制平面](https://kubernetes.io/docs/concepts/overview/components/#control-plane-components)和 Etcd。

![components-of-kubernetes](/images/components-of-kubernetes.png)

如果集群中 master 节点变得不可用了，虽然已经在运行的 pod**可能**不会收到影响，但是集群中的调度、弹性伸缩、集群网络等功能都会因此受到影响。因此维护好一个 Kubernetes 的可用性将会在很大程度上影响到集群中应用的可用性。

提到可用性，我们首先想到的就是增加冗余节点，避免单点故障。但是在 kuberntes 集群中，双主的架构非但不能为集群提高可用性，反而会使集群的可用性减半，这又是怎么一回事呢？

## Raft

其实在控制平面中，除了 etcd 之外的组件我们都可以视为无状态的组件，可以随意的通过横向扩展来提升可用性和吞吐能力的。但是其中的 etcd 则是一个有状态的组件，多个 etcd 之间需要相互通信并保持同步。在 etcd 中，集群中的节点达成共识的方法是通过一种叫`raft`的共识算法实现的。关于 raft 集群的运行，可以通过这个[链接](http://thesecretlivesofdata.com/raft/)来观察其运行方式。

简单来说，在基于 raft 实现的分布式集群中也是存在主从关系的，即 Leader、Follower、Candidate 三种类型的节点。其中，集群唯一 Leader 节点负责处理请求，并在集群内的大多数节点（集群总节点数/2+1）同意更改后，将请求内容同步到其他的节点中。

当一个只有两个节点的 etcd 集群中有节点不可用后，视节点类型会有以下两种情况：

- Leader 节点不可用，剩下的 Follower 在下一个任期开始时转变为 Candidate 并发起选举。但是始终收不到集群内大多数节点（集群总节点数/2+1 即两个节点，但是集群内算上自己也就只剩一个节点活着了）的同意，故 Leader 将始终无法选举，最终导致 etcd 集群不可用。
- Follower 节点不可用，Leader 在心跳超时后会认为自己以及失去了大部分节点的支持，继而变为 Follower 节点，并在下一个任期开始时继续降级为 Candidate，并重复进行无法产生结果的选举。

也就是说，但 etcd 集群的大小为 2 的时候，集群的容错能力任然得不到提升，任意一个节点的不可用都会导致整个 etcd 集群的不可用。

## 建议
偶数个节点的集群非但不能提升容错能力，反而会带来资源的浪费并可能使选举的时间变长。同时在奇数个集群的情况下，即使产生网络分区也能保证始终有一方占据大多数的节点，进而选举出新的Leader来保证集群的可用。而偶数个节点则可能会出现对半分的场景，这样任意一方都无法选举出Leader，导致集群的不可用。

[官方](https://etcd.io/docs/v3.4.0/faq/)也给出了一个表格来直观的阐述集群大小和容错能力的关系，就希望不要真有人弄偶数个节点的集群了。

| 集群大小 | 大多数所指的数量 | 容错能力 |
|:-:|:-:|:-:|
| 1 | 1 | 0 |
| 2 | 2 | 0 |
| 3 | 2 | 1 |
| 4 | 3 | 1 |
| 5 | 3 | 2 |
| 6 | 4 | 2 |
| 7 | 4 | 3 |
| 8 | 5 | 3 |
| 9 | 5 | 4 |

## 总结
其实etcd和控制平面是没有必要一定在相同节点的，在创建集群和添加节点时没必要捆绑将控制平面和etcd捆绑在一起。使用外部的etcd集群可以帮助我们更好的调度资源的分配。不过具体是否使用外部etcd集群还是视实际状况而定。

下一期应该也是和 etcd 相关的实际运行中的问题，总感觉 kubernetes 集群出问题多多少少都和 etcd 有点关系。未来可能还会带来一些网络问题和内核问题的介绍，希望多少能给大家带来一些帮助，避免在重复的问题上踩坑。
