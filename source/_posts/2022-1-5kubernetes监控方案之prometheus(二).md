---
title: Kubernetes监控方案之prometheus(二)
date: 2022-1-5
updated: 2022-1-5
categories:
  - Record
index_img: /img/prometheus.png
tags:
  - Kubernetes
  - prometheus
  - node_exporter




---

## exporter简介

Prometheus已经成为云原生应用监控行业的标准，在很多流行的监控系统中都已经实现了Prometheus的监控接口，例如etcd、Kubernetes、CoreDNS等，他们可以直接被Prometheus监控，但是大多数监控对象都没办法直接提供监控接口，主要原因有

(1) 很多系统在Prometheus诞生前很多年就已经发布，例如MySQL、Redis等

(2) 它们本身不支持HTTP接口，例如对于硬件性能指标，操作系统并没有原生的HTTP接口可以获取；

(3) 考虑到安全性、稳定性及代码耦合等因素的影响

在这个背景之下，`exporter`诞生，**exporter是一个采集监控数据并通过Prometheus监控规范对外提供数据的组件。**除了官方实现的exporter如Node exporter、HAProxy exporter、Mysql exporter，还有很多第三方的如Redis exporter和Rabbitmq exporter

![image-20220105162805034](https://tva1.sinaimg.cn/large/008i3skNgy1gy2vl97diaj30t50dm75b.jpg)

这些exporter主要通过被监控对象提供的监控相关的接口获取监控数据，这些接口主要通过以下方式对外提供服务。

(1) HTTP/HTTPS方式。例如Rabbitmq exporter通过Rabbitmq的HTTPS接口获取监控数据

(2) TCP方式。例如Redis exporter通过Redis提供的系统监控相关命令获取监控指标，MySQL server exporter 通过MySQL开放的监控相关的表获取监控指标

(3) 本地文件方式。 例如Node exporter通过读取proc文件系统下的文件，计算得出整个操作系统状态

(4) 标准协议方式。例如IPMI exporter通过IPMI协议获取硬件相关信息。这些exporter将不同规范和格式的监控指标进行转化，输出prometheus能够识别的监控数据格式，从而极大扩展prometheus采集数据的能力

对于Kubernetes的集群监控一般我们需要考虑一下几方面

- Kubernetes节点的监控；比如节点的cpu、load、fdisk、memory等指标
- 内部系统组件的状态；比如kube-scheduler、kube-controller-manager、kubedns/coredns等组件的运行状态
- 编排级的metrics；比如Deployment的状态、资源请求、调度和API延迟等数据指标

## 监控方案

Kubernetes集群的监控方案主要有以下几种方案

- Heapster:Herapster是一个集群范围的监控和数据聚合工具，以Pod的形式运行在集群中

![image-20220105162914609](https://tva1.sinaimg.cn/large/008i3skNly1gy2vmgiiftj30ib074mxe.jpg)

- cAvisor:[cAdvisor](https://github.com/google/cadvisor)是Google开源的容器资源监控和性能分析工具，它是专门为容器而生，本身也支持Docker容器，Kubernetes中，我们不需要单独去安装，cAdvisor作为kubelet内置的一部分程序可以直接使用
- [Kube-state-metrics](https://github.com/kubernetes/kube-state-metrics):通过监听API Server生成有关资源对象的状态指标，比如Deployment、Node、Pod，需要注意的是kube-state-metrics只是简单的提供一个metrics数据，并不会存储这些指标数据，所以我们可以使用Prometheus来抓取这些数据然后存储
- metrics-server:metrics-server也是一个集群范围内的资源数据局和工具，是Heapster的代替品，同样的，metrics-server也只是显示数据，并不提供数据存储服务。

不过`kube-state-metrics`和`metrics-server`之前还有很大不同的，二者主要区别如下

```
1.kube-state-metrics主要关注的是业务相关的一些元数据，比如Deployment、Pod、副本状态等2.metrics-service主要关注的是资源度量API的实现，比如CPU、文件描述符、内存、请求延时等指标
```

首先需要我们监控集群的节点，要监控节点其实我们已经有很多非常成熟的方案了，比如Nagios、Zabbix，甚至可以我们自己收集数据，这里我们通过prometheus来采集节点的监控指标，可以通过node_exporter获取，node_exporter就是抓取用于采集服务器节点的各种运行指标，目前node_exporter几乎支持所有常见的监控点，比如cpu、distats、loadavg、meminfo、netstat等，详细的监控列表可以参考[github repo](https://github.com/prometheus/node_exporter)

这里使用`DeamonSet`控制器来部署该服务，这样每一个节点都会运行一个Pod，如果我们从集群中删除或添加节点后，也会进行自动扩展

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: kube-system
  labels:
    app: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      hostPID: true
      hostIPC: true
      hostNetwork: true
      containers:
      - name: node-exporter
        image: prom/node-exporter:v0.17.0
        ports:
        - containerPort: 9100
        resources:
          requests:
            cpu: 0.15
        securityContext:
          privileged: true
        args:
        - --path.procfs
        - /host/proc
        - --path.sysfs
        - /host/sys
        - --collector.filesystem.ignored-mount-points
        - '"^/(sys|proc|dev|host|etc)($|/)"'
        volumeMounts:
        - name: dev
          mountPath: /host/dev
        - name: proc
          mountPath: /host/proc
        - name: sys
          mountPath: /host/sys
        - name: rootfs
          mountPath: /rootfs
      tolerations:
      - key: "node-role.kubernetes.io/master"
        operator: "Exists"
        effect: "NoSchedule"
      volumes:
        - name: proc
          hostPath:
            path: /proc
        - name: dev
          hostPath:
            path: /dev
        - name: sys
          hostPath:
            path: /sys
        - name: rootfs
          hostPath:
            path: /

```

```yaml
[root@elk-dns-prod02-brainup ~]# kubectl create -f prometheus-node-exporter.yaml
[root@elk-dns-prod02-brainup ~]# kubectl get pod -n kube-system -o wide|grep node-expo
node-exporter-8xfsw                                  1/1     Running   0                 29h   192.168.0.210     elk-dns-prod02-brainup.com   <none>           <none>
node-exporter-dqp8s                                  1/1     Running   0                 29h   192.168.0.208     elk-dns-prod05-brainup.com   <none>           <none>
node-exporter-fb8g9                                  1/1     Running   0                 29h   192.168.0.209     elk-dns-prod04-brainup.com   <none>           <none>
node-exporter-k2ql9                                  1/1     Running   0                 29h   192.168.0.206     elk-dns-prod03-brainup.com   <none>           <none>
node-exporter-txwkt                                  1/1     Running   0                 29h   192.168.0.207     elk-dns-prod06-brainup.com   <none>           <none>
node-exporter-wcz5b                                  1/1     Running   0                 29h   192.168.0.211     elk-dns-prod01-brainup.com   <none>           <none>
#这里我们可以看到，我们有4个节点，在所有的节点上都启动了一个对应Pod进行获取数据
```

**node-exporter.yaml文件说明**

由于我们要获取的数据是主机的监控指标数据，而我们的node-exporter是运行在容器中的，所以我们在Pod中需要配置一些Pod的安全策略

```
hostPID:truehostIPC:truehostNetwork:true #这三个配置主要用于主机的PID namespace、IPC namespace以及主机网络，这里需要注意的是namespace是用于容器隔离的关键技术，这里的namespace和集群中的namespace是两个完全不同的概念
```

另外我们还需要将主机`/dev`、`/proc`、`/sys`这些目录挂在到容器中，这些因为我们采集的很多节点数据都是通过这些文件来获取系统信息

另外如果是使用`kubeadm`搭建的，同时需要监控master节点的，则需要添加下方的相应容忍

```yaml
      - key: "node-role.kubernetes.io/master"
        operator: "Exists"
        effect: "NoSchedule
```

node-exporter容器相关启动参数

```yaml
args:
        - --path.procfs     #配置挂载宿主机（node节点）的路径
        - /host/proc
        - --path.sysfs      #配置挂载宿主机（node节点）的路径
        - /host/sys
        - --collector.filesystem.ignored-mount-points
        - '"^/(sys|proc|dev|host|etc)($|/)"'
```

我们检查exporter是否有报错

```shell
[root@elk-dns-prod02-brainup ~]# kubectl logs -n kube-system node-exporter-8xfsw
```

![image-20220105163353218](https://tva1.sinaimg.cn/large/008i3skNly1gy2vrau7w5j31m20u04a8.jpg)

```shell
#接下来，我们在任意集群节点curl 9100/metrics
 
curl 127.0.0.1:9100/metrics
...
node_xfs_block_mapping_extent_list_insertions_total{device="vda2"} 0
node_xfs_block_mapping_extent_list_insertions_total{device="vda3"} 285586
# HELP node_xfs_block_mapping_extent_list_lookups_total Number of extent list lookups for a filesystem.
# TYPE node_xfs_block_mapping_extent_list_lookups_total counter
node_xfs_block_mapping_extent_list_lookups_total{device="vda2"} 27
node_xfs_block_mapping_extent_list_lookups_total{device="vda3"} 5.3729641e+07
# HELP node_xfs_block_mapping_reads_total Number of block map for read operations for a filesystem.
# TYPE node_xfs_block_mapping_reads_total counter
...
 
#只要metrics可以获取到数据说明node-exporter没有问题
```

## 服务发现

我们这里三个节点都运行了`node-exporter`程序，如果我们通过一个Server来将数据收集在一起，用静态的方式配置到prometheus就会显示一条数据，我们得自己在指标中过滤每个节点的数据，配置比较麻烦。 这里就采用服务发现

在Kubernetes下，Prometheus通过Kubernetes API基础，目前主要支持5种服务发现，分别是`node`、`Server`、`Pod`、`Endpoints`、`Ingress`

我们需要在prometheus配置文件中添加如下三行

```yaml
- job_name: 'kubernetes-node'
      kubernetes_sd_configs:
      - role: node
 
#通过制定Kubernetes_sd_config的模式为node，prometheus就会自动从Kubernetes中发现所有的node节点并作为当前job监控的目标实例，发现的节点/metrics接口是默认的kubelet的HTTP接口
```

```shell
[root@elk-dns-prod02-brainup prometheus]# kubectl delete -f prometheus-configmap.yaml
[root@elk-dns-prod02-brainup prometheus]# kubectl apply -f prometheus-configmap.yaml
[root@elk-dns-prod02-brainup prometheus]# kubectl get svc -n kube-system |grep prometheus
prometheus             NodePort    10.101.143.162           9090:32331/TCP           21h
 
#热更新刷新配置（可能稍微需要等待一小会）
[root@elk-dns-prod02-brainup prometheus]# curl -X POST http://10.101.143.162:9090/-/reload
```

现在我们可以看到已经获取到我们的Node节点的IP，但是由于metrics监听的端口是10250而并不是我们设置的9100，所以提示我们节点属于Down的状态

![image-20220105163716440](https://tva1.sinaimg.cn/large/008i3skNly1gy2vut79sdj319x0l80we.jpg)

这里我们就需要使用Prometheus提供的`relabel_configs`中的`replace`能力了，relabel可以在Prometheus采集数据之前，通过Target实例的Metadata信息，动态重新写入Label的值。除此之外，我们还能根据Target实例的Metadata信息选择是否采集或者忽略该Target实例。这里使用`__address__`标签替换10250端口为9100

这里使用正则进行替换端口

```yaml
 - job_name: 'kubernetes-node'
      kubernetes_sd_configs:
      - role: node
      relabel_configs:
      - source_labels: [__address__]
        regex: '(.*):10250'
        replacement: '${1}:9100'
        target_label: __address__
        action: replace
```

接下来我们重新apply一下configmap文件

```shell
[root@elk-dns-prod02-brainup prometheus]# kubectl delete -f prometheus-configmap.yaml
[root@elk-dns-prod02-brainup prometheus]# kubectl apply -f prometheus-configmap.yaml
[root@elk-dns-prod02-brainup prometheus]# curl -X POST http://10.101.143.162:9090/-/reload
```

查看状态发现已经up了

![image-20220105163900811](https://tva1.sinaimg.cn/large/008i3skNly1gy2vwms1aqj31kc0u0dqc.jpg)

目前状态已经正常，但是还有一个问题就是我们的采集数据只显示了IP地址，对于我们监控分组分类不是很方便，这里可以通过`labelmap`这个属性来将Kubernetes的Label标签添加为Prometheus的指标标签

```yaml
- job_name: 'kubernetes-node'
      kubernetes_sd_configs:
      - role: node
      relabel_configs:
      - source_labels: [__address__]
        regex: '(.*):10250'
        replacement: '${1}:9100'
        target_label: __address__
        action: replace
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
```

![image-20220105164007436](https://tva1.sinaimg.cn/large/008i3skNgy1gy2vxs9fctj31qq0s0dnh.jpg)

## 一、容器监控

cAdvisor是一个容器资源监控工具，包括容器的内存，CPU，网络IO，资源IO等资源，同时提供了一个Web页面用于查看容器的实时运行状态。

cAvisor已经内置在了kubelet组件之中，所以我们不需要单独去安装，cAdvisor的数据路径为`/api/v1/nodes//proxy/metrics`

```yaml
- job_name: 'kubernetes-cadvisor'
      kubernetes_sd_configs:
      - role: node
      scheme: https
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
      - target_label: __address__
        replacement: kubernetes.default.svc:443
      - source_labels: [__meta_kubernetes_node_name]
        regex: (.+)
        target_label: __metrics_path__
        replacement: /api/v1/nodes/${1}/proxy/metrics/cadvisor
```

这里稍微说一下tls_config配置的证书地址是每个Pod连接apiserver所使用的地址，基本上写死了。并且我们在配置文件添加了一个labelmap标签。在最下面使用了一个正则替换了cAdvisor的一个metrics地址

> 证书是我们Pod启动的时候kubelet给pod注入的一个证书，所有的pod启动的时候都会有一个ca证书注入进来

重新apply修改过的configmap文件验证即可

## 二、Api-Service 监控

apiserver作为Kubernetes最核心的组件，它的监控也是非常有必要的，对于apiserver的监控，我们可以直接通过kubernetes的service来获取

```shell
[root@root@elk-dns-prod02-brainup prometheus]# kubectl get svc
NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1            443/TCP   33d
```

上面的service是我们集群的apiserver内部的service的地址，要自动发现service类型的服务，需要使用`role`为`Endpoints`的`kubernetes_sd_configs (自动发现)`，我们只需要在configmap里面在添加Endpoints类型的服务发现

```
   - job_name: 'kubernetes-apiserver'
     kubernetes_sd_configs:
     - role: endpoints
```

刷新配置文件，最好是多刷新几次

更新完成后，我们可以看到kubernetes-apiserver下面出现了很多实例，这是因为我们这里使用的Endpoints类型的服务发现，所以prometheus把所有的Endpoints服务都抓取过来了，同样的我们要监控的kubernetes也在列表中。

![image-20220105164316321](https://tva1.sinaimg.cn/large/008i3skNgy1gy2w124zxcj31180kr0w9.jpg)

这里我们使用`keep`动作，将符合配置的保留下来，例如我们过滤default命名空间下服务名称为`kubernetes`的元数据，这里可以根据`__meta_kubernetes_namespace`和`__mate_kubertnetes_service_name`2个元数据进行relabel

```yaml
- job_name: 'kubernetes-apiservers'
      kubernetes_sd_configs:
      - role: endpoints
      scheme: https
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: default;kubernetes;https
 
#参数解释
action: keep  #保留哪些标签
regex: default;kubernetes;https  #匹配namespace下的default命名空间下的kubernetes service 最后https协议
可以通过`kubectl describe svc kubernetes`查看到
```

刷新配置查看

![image-20220105164427904](https://tva1.sinaimg.cn/large/008i3skNly1gy2w2asv4ij30w408ndgg.jpg)

如果我们要监控其他系统组件，比如kube-controller-manager、kube-scheduler的话就需要单独手动创建service，因为apiserver服务默认在default，而其他组件在kube-steam这个namespace下。其中kube-sheduler的指标数据端口为`10251`，kube-controller-manager对应端口为`10252`

## 三、Service 监控

apiserver实际上是一种特殊的Service，现在配置一个专门发现普通类型的Service

> 这里我们对service进行过滤，只有在service配置了`prometheus.io/scrape: "true"`过滤出来

```yaml
    - job_name: 'kubernetes-service-endpoints'
      kubernetes_sd_configs:
      - role: endpoints
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scheme]
        action: replace
        target_label: __scheme__
        regex: (https?)
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
      - action: labelmap
        regex: __meta_kubernetes_service_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_service_name]
        action: replace
        target_label: kubernetes_name
```

刷新配置查看

```yaml
#1.参数解释
relabel_configs:
-source_labels:[__meta_kubernetes_service_annotation_prometheus_io_scrape]
action: keep 
regex: true  保留标签
source_labels: [__meta_kubernetes_service_annotation_prometheus_io_cheme]
 
这行配置代表我们只去筛选有__meta_kubernetes_service_annotation_prometheus_io_scrape的service，只有添加了这个声明才可以自动发现其他service
 
#2.参数解释
  - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
    action: replace
    target_label: __address__
    regex: ([^:]+)(?::\d+)?;(\d+)
    replacement: $1:$2
#指定一个抓取的端口，有的service可能有多个端口（比如之前的redis）。默认使用的是我们添加是使用kubernetes_service端口
 
#3.参数解释
  - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scheme]
    action: replace
    target_label: __scheme__
    regex: (https?)
#这里如果是https证书类型，我们还需要在添加证书和token
```

至此我们的prometheus监控k8s已经完成啦,下一站我们将介绍如何使用grafana接入prometheus并查看数据
