---
title: Kubernetes监控方案之prometheus(一)
date: 2022-1-5
updated: 2022-1-5
categories:
  - Record
index_img: /img/prometheus.png
tags:
  - Kubernetes
  - prometheus



---

Prometheus由Go语言编写而成，采用Pull方式获取监控信息，并提供了多维度的数据模型和灵活的查询接口。Prometheus不仅可以通过静态文件配置监控对象，还支持自动发现机制，能通过Kubernetes、Consl、DNS等多种方式动态获取监控对象。在数据采集方面，借助Go语音的高并发特性，单机Prometheus可以采取数百个节点的监控数据；在数据存储方面，随着本地时序数据库的不断优化，单机Prometheus每秒可以采集一千万个指标，如果需要存储大量的历史监控数据，则还支持远程存储。

## Prometheus 简介

Prometheus是由SoundCloud开发的开源监控系统的开源版本。2016年，由Google发起的Linux基金会(Cloud Native Computing Foundation,CNCF)将Prometheus纳入其第二大开源项目。Prometheus在开源社区也十分活跃

**Prometheus优缺点**

```
1.提供多维度数据模型和灵活的查询方式，通过将监控指标关联多个tag，来将监控数据进行任意维度的组合，并且提供简单的PromQL查询方式，还提供HTTP查询接口，可以很方便地结合Grafana等GUI组件展示数据 2.在不依赖外部存储的情况下，支持服务器节点的本地存储，通过Prometheus自带的时序数据库，可以完成每秒千万级的数据存储；不仅如此，在保存大量历史数据的场景中，Prometheus可以对接第三方时序数据库和OpenTSDB等。 3.定义了开放指标数据标准，以基于HTTP的Pull方式采集时序数据，只有实现了Prometheus监控数据才可以被Prometheus采集、汇总、并支持Push方式向中间网关推送时序列数据，能更加灵活地应对多种监控场景 4.支持通过静态文件配置和动态发现机制发现监控对象，自动完成数据采集。Prometheus目前已经支持Kubernetes、etcd、Consul等多种服务发现机制 5.易于维护，可以通过二进制文件直接启动，并且提供了容器化部署镜像。 6.支持数据的分区采样和联邦部署，支持大规模集群监控
```

**Prometheus 架构**

Prometheus的基本原理是通过HTTP周期性抓取被监控组件的状态，任意组件只要提供对应的HTTP接口并符合Prometheus定义的数据格式，就可以介入Prometheus监控

![image-20220105160247307](https://tva1.sinaimg.cn/large/008i3skNgy1gy2uv16ektj315y0rzwh6.jpg)

Prometheus Server负载定时在目标上抓取metrics(指标)数据，每个抓取目标都需要暴露一个HTTP服务接口用于Prometheus定时抓取。这种调用被监控对象获取监控数据的方式被称为Pull(拉)。Pull方式体现了Prometheus独特的设计哲学与大多数采用Push(推)方式的监控不同

**Prometheus支持两种Pull方式采集数据**

- 通过配置文件、文本等进行静态配置
- 支持Zookeeper、Consul、Kubernetes等方式进行动态发现，例如对Kuernetes的动态发现，Prometheus使用Kubernetes的API查询和监控容器信息的变化，动态更新监控对象，这样容器的创建和删除都可以被Prometheus感知

Storage通过一定的规则清理和整理数据，并把得到的结果从年初到新的时间序列中，这里存储的方式有两种

1.本地存储。通过Prometheus自带的时序数据库将数据库数据保存在本地磁盘。但是本地存储的容量毕竟有限，建议不要保存超过一个月的数据

2.另一种是远程存储，适用于存储大量监控数据。通过中间层的适配器的转发，目前Prometheus支持OpenTsdb、InfluxDB、Elasticsearch等后端存储，通过适配器实现Prometheus存储的remote write和remote read接口，便可以接入Prometheus作为远程存储使用。

Prometheus通过PromQL和其他API可视化地展示收集的数据。Prometheus支持多种方式的图标可视化，例如Grafana、自带的PromDash及自身提供的模板引擎等。Prometheus还提供HTTP API查询方法，自定义所需要的输出

Prometheus通过Pull方式拉取数据，但某些现有系统是通过Push方式实现的，为了接入这些系统，Prometheus提供了对PushGateway的支持，这些系统主动推送`metrics`到PushGateway，而Prometheus只是定时去Gateway上抓取数据

![image-20220105160337723](https://tva1.sinaimg.cn/large/008i3skNgy1gy2uvt7vnpj30k2082q3c.jpg)

## Prometheus特征

Prometheus 相比于其他传统监控工具主要由以下几个特点

- 具有由metric名称和键值对标示的时间序列数据的多位数据模型
- 有一个灵活的查询语言`promQL`
- 不依赖分布式存储，只和本地磁盘有关
- 通过HTTP的服务拉取时间序列数据
- 也支持推送的方式来添加时间序列数据
- 支持通过服务发现和静态配置发现目标
- 多种图形和仪表盘支持

## Prometheus 组件

Prometheus由多个组件组成，但是其中许多组件是可选的；

- Prometheus Server 用于抓取指标、存储时间序列数据
- exporter 暴露指标让任务抓取
- Pushgateway push的方式将指标数据推送到网关
- alertmanager 处理报警的报警组件
- adhoc 用于数据查询

大多数Prometheus组件都是使用go编写的，因此很容易构建和部署静态的二进制文件

![image-20220105160412371](https://tva1.sinaimg.cn/large/008i3skNgy1gy2uwesdrmj311e0nn419.jpg)

prometheus的方式有很多，为了兼容k8s环境，我们将prometheus搭建在k8s里，除了使用docker镜像的方式安装，还可以使用二进制的方式进行安装，支持mac、Linux、windows



我们prometheus采用直接创建pv的方式来存储数据，同时使用configMap管理配置文件。并且我们将所有的prometheus存储在`kube-system`

 ```yaml
 #建议将所有的prometheus yaml文件存在一块
 mkdir /opt/prometheus -p && cd /opt/prometheus
 
 prometheus-configmap.yaml
 
 apiVersion: v1
 kind: ConfigMap
 metadata:
   name: prometheus-config
   namespace: kube-system
 data:
   prometheus.yml: |
     global:
       scrape_interval: 15s
       scrape_timeout: 15s
     scrape_configs:
     - job_name: 'prometheus'
       static_configs:
       - targets: ['localhost:9090']
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
         
         
         # 配置文件解释（这里的configmap实际上就是prometheus的配置）
 上面包含了3个模块global、rule_files和scrape_configs
  
 其中global模块控制Prometheus Server的全局配置
 scrape_interval:表示prometheus抓取指标数据的频率，默认是15s，我们可以覆盖这个值
 evaluation_interval:用来控制评估规则的频率，prometheus使用规则产生新的时间序列数据或者产生警报
  
 rule_files模块制定了规则所在的位置，prometheus可以根据这个配置加载规则，用于生产新的时间序列数据或者报警信息，当前我们没有配置任何规则，后期会添加
  
 scrape_configs用于控制prometheus监控哪些资源。由于prometheus通过http的方式来暴露它本身的监控数据，prometheus也能够监控本身的健康情况。在默认的配置有一个单独的job，叫做prometheus，它采集prometheus服务本身的时间序列数据。这个job包含了一个单独的、静态配置的目标；监听localhost上的9090端口。
 prometheus默认会通过目标的/metrics路径采集metrics。所以，默认的job通过URL：http://localhost:9090/metrics采集metrics。收集到时间序列包含prometheus服务本身的状态和性能。如果我们还有其他的资源需要监控，可以直接配置在该模块下即可
 
 ```

我们这里暂时只配置了对 prometheus 的监控，然后创建该资源对象：

```
[root@elk-dns-prod02-brainup prometheus]# kubectl apply -f prometheus-configmap.yaml
[root@elk-dns-prod02-brainup prometheus]# kubectl get configmaps -n kube-system |grep prometheus
prometheus-config                    1      25h
```

现在创建配置文件完成，如果后期有需要新加的监控项目直接更新configmap即可，现在我们开始创建prometheus的Pod资源

```yaml
apiVersion: apps/v1 
kind: Deployment
metadata:
  name: prometheus
  namespace: kube-system
  labels:
    app: prometheus
spec:
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      serviceAccountName: prometheus
      containers:
      - image: prom/prometheus:v2.4.3
        name: prometheus
        command:
        - "/bin/prometheus"
        args:
        - "--config.file=/etc/prometheus/prometheus.yml"
        - "--storage.tsdb.path=/prometheus"
        - "--storage.tsdb.retention=30d"
        - "--web.enable-admin-api"   # 控制对admin HTTP API的访问，其中包括删除时间序列等功能
        - "--web.enable-lifecycle"   #支持热更新，直接执行localhost:9090/-/reload立即生效
        ports:
        - containerPort: 9090
          protocol: TCP
          name: http
        volumeMounts:
        - mountPath: "/prometheus"
          subPath: prometheus
          name: data
        - mountPath: "/etc/prometheus"
          name: volume-pro
        resources:
          requests:
            cpu: 100m
            memory: 512Mi
          limits:
            cpu: 100m
            memory: 512Mi
      securityContext:
        runAsUser: 0
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: prometheus-pv-claim
      - configMap:
          name: prometheus-config
        name: volume-pro

```

```
[root@elk-dns-prod02-brainup prometheus]# kubectl apply -f prometheus-depl.yaml
[root@elk-dns-prod02-brainup prometheus]# kubectl get po -n kube-system  | grep prome
prometheus-64c8d9c767-8qnx8                          1/1     Running   136 (3m20s ago)   24h
```

我们在启动程序的时候，除了指定`prometheus.yaml`(configmap)以外，还通过`storage.tsdb.path`指定了TSDB数据的存储路径、通过`storage.tsdb.rentention`设置了保留多长时间的数据，还有下面的web.enable-admin-api参数可以用来开启对admin api的访问权限，参数`web.enable-lifecyle`用来开启支持热更新，有了这个参数之后，`prometheus.yaml`(configmap)文件只要更新了，通过执行`localhost:9090/-/reload`就会立即生效

我们添加了一行securityContext，，其中`runAsUser`设置为0，这是因为prometheus运行过程中使用的用户是nobody，如果不配置可能会出现权限问题。



prometheus.yaml文件对应的ConfigMap对象通过volume的形式挂载进Pod，这样ConfigMap更新后，对应的pod也会热更新，然后我们在执行上面的reload请求，prometheus配置就生效了。除此之外，对了将时间数据进行持久化，我们将数据目录和一个pvc对象进行了绑定，所以我们需要提前创建pv，pvc对象

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-pv-volume
  namespace: kube-system
  labels:
    type: local
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/mnt/prometheus"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-pv-claim
  namespace: kube-system
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi

```

```
[root@elk-dns-prod02-brainup prometheus]# kubectl apply -f prometheus-pv-pvc.yaml
[root@elk-dns-prod02-brainup prometheus]# kubectl get pv,pvc -n kube-system
NAME                                    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                             STORAGECLASS   REASON   AGE
persistentvolume/chandao-pv             20Gi       RWO            Retain           Bound    seafile/chandao-pv-date                                   23d
persistentvolume/chandao-pv-volume      20Gi       RWO            Retain           Bound    seafile/chandao-pv-claim                                  23d
persistentvolume/grafana-pv-volume      20Gi       RWO            Retain           Bound    kube-system/grafana-pv-claim                              23h
persistentvolume/mysql-pv-volume        20Gi       RWO            Retain           Bound    seafile/mysql-pv-claim                                    23d
persistentvolume/prometheus-pv-volume   20Gi       RWO            Retain           Bound    kube-system/prometheus-pv-claim                           24h

NAME                                        STATUS   VOLUME                 CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistentvolumeclaim/grafana-pv-claim      Bound    grafana-pv-volume      20Gi       RWO                           23h
persistentvolumeclaim/prometheus-pv-claim   Bound    prometheus-pv-volume   20Gi       RWO                           24h
```

**这里稍微提示一下，我们创建的pv和pvc大小都是10g，只是测试存储为10g。线上可以修改为200或者更多，一般prometheus数据保留15-30天就可以，如果数据量过大建议使用TSBD分布式存储**

我们这里还需要创建rbac认证，因为prometheus需要访问k8s集群内部的资源

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups:
  - ""
  resources:
  - nodes
  - services
  - endpoints
  - pods
  - nodes/proxy
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - configmaps
  - nodes/metrics
  verbs:
  - get
- nonResourceURLs:
  - /metrics
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: kube-system

```

```shell
[root@elk-dns-prod02-brainup prometheus]# kubectl apply -f prometheus-rbac.yaml
```

现在我们prometheus服务状态是已经正常了，但是我们在浏览器是无法访问prometheus的 webui服务。那么我们还需要创建一个service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: kube-system
  labels:
    app: prometheus
spec:
  selector:
    app: prometheus
  type: NodePort
  ports:
    - name: web
      port: 9090
      targetPort: http

```

```shell
[root@elk-dns-prod02-brainup prometheus]# kubectl apply -f prometheus-rbac.yaml
```

这里定义的端口为32331,我们直接在浏览器上**任意节点**输入ip+端口即可

![image-20220105160114179](https://tva1.sinaimg.cn/large/008i3skNgy1gy2utpnglcj316r0czwfe.jpg)