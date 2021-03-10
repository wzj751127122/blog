---
title: Kubernetes Deployment 故障排查指南
date: 2021-03-8
updated: 2021-03-8
categories:
  - Record
index_img: /img/k8s1.png
tags:
  - Kubernetes
  - Deployment
  - Service
---

### Deployment

![image-20210308092200097](/images/Deployment-Troubleshooting/depl1.png)

如果你不知道从何下手，那么在 Kubernetes 中排查故障可能会是一项艰难的任务。文本以超详细的图解说明了如何对 Kubernetes Deployment 进行故障排查，相信会对你有启发。

下面这张图可以帮助你调试 Kubernetes 中的 Deployment

![image-20210308092835090](/images/Deployment-Troubleshooting/depl2.png)

![image-20210308092856458](/images/Deployment-Troubleshooting/depl3.png)

当你想要在 Kubernetes 中部署应用程序时，通常需要定义 3 个组件：

- **Deployment**：创建 Pod 副本的方法；
- **Service**：内部负载均衡器，将流量路由到 Pod；
- **Ingress**：描述流量如何从外部集群流向 Service。

可以用下面的示意图来简单说明。

![image-20210308092916360](/images/Deployment-Troubleshooting/depl4.png)

<center>Kubernetes 中应用程序通过内部和外部两层负载均衡器暴露</center>

![image-20210308092944444](/images/Deployment-Troubleshooting/depl5.png)
内部负载均衡器叫 Service，外部负载均衡器叫 Ingress

![image-20210308093004987](/images/Deployment-Troubleshooting/depl6.png)

<center>Pod 不是直接部署的。相反，Deployment 会创建 Pod，并监控 Pod</center>



假设你希望部署一个简单的 Hello World 应用程序，这个应用程序的 YAML 应该类似于如下内容：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  labels:
    track: canary
spec:
  selector:
    matchLabels:
      any-name: my-app
  template:
    metadata:
      labels:
        any-name: my-app
    spec:
      containers:
        - name: cont1
          image: learnk8s/app:1.0.0
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  ports:
    - port: 80
      targetPort: 8080
  selector:
    name: app
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
spec:
  rules:
  - http:
      paths:
      - backend:
          service:
            name: my-service
            port:
              number: 80
        path: /
        pathType: Prefix
```

定义很长，很容易忽略组件之间的相互关系。例如：

- 何时应使用端口 80，何时应使用端口 8080？
- 是否应该为每个服务创建一个新端口，以免冲突？
- 标签（label）名称重要吗？应该保持标签名称一致吗？

在进行调试之前，让我们回顾一下这三个组件之间的关系。我们从 Deployment 和 Service 开始。

连接 Deployment 和 Service

令人惊讶的是，**Deployment 和 Service 之间根本没有连接**。**相反，Service 直接指向 Pod，完全跳过了 Deployment**。因此，你应该关注的是 Pod 和 Service 之间是如何相互关联的。

请记住以下三件事：


- Service selector 应至少匹配 Pod 的一个标签；
- Service 的 targetPort 应该与 Pod 的 containerPort 匹配；
- Service 端口可以是任何数字。多个 Service 可以使用同一个端口，因为每个 Service 分配到的 IP 地址不同。


下图总结了如何连接端口：


![image-20210308093139747](/images/Deployment-Troubleshooting/depl7.png)

<center>考虑通过 Service 暴露的以下 Pod</center>

![image-20210308093201956](/images/Deployment-Troubleshooting/depl8.png)

<center>在创建 Pod 时，需要为 Pod 中的每个容器定义端口 containerPort</center>

![image-20210308093222521](/images/Deployment-Troubleshooting/depl9.png)

<center>创建 Service 时，可以定义 port 和 targetPort。但是哪一个应该和容器连接呢</center>

![image-20210308093237074](/images/Deployment-Troubleshooting/depl10.png)

<center>targetPort 和 conatinerPort 需始终匹配</center>

![image-20210308093257499](/images/Deployment-Troubleshooting/depl11.png)

<center>如果容器暴露的是端口 3000，那么 targetPort 应该也是 3000</center>

如果查看 YAML 文件，标签和 port/targetPort 应该是匹配的。

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  labels:
    track: canary
spec:
  selector:
    matchLabels:
      any-name: my-app
  template:
    metadata:
      labels:
        any-name: my-app
    spec:
      containers:
        - name: cont1
          image: learnk8s/app:1.0.0
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  ports:
    - port: 80
      targetPort: 8080
  selector:
    any-name: my-app
```

那 Deployment 顶部的 track：canary 标签呢？也要匹配上吗？

这个标签也属于 Deployment，但 Service selector 不使用它来路由流量。换句话说，你可以放心地删除它或为它分配别的值。

那 matchLables selector 呢？它必须始终与 Pod 的标签匹配，Deployment 用它来跟踪 Pod。

假设你做了正确的更改，你应该如何测试它呢？可以使用以下命令检查 Pod 是否具有正确的标签：

```
kubectl get pods --show-labels
NAME                  READY   STATUS    LABELS
my-deployment-pv6pd   1/1     Running   any-name=my-app,pod-template-hash=7d6979fb54
my-deployment-f36rt   1/1     Running   any-name=my-app,pod-template-hash=7d6979fb54
```

或者如果有属于多个应用程序的 Pod：

```
kubectl get pods --selector any-name=my-app --show-labels
```

其中 any-name=my-app是any-name：my-app标签。

仍然有问题？你也可以连接到 Pod！可以在 kubectl 中使用 port-forward 命令来连接到 Service 并测试该连接。

```
kubectl port-forward service/<service name> 3000:80
Forwarding from 127.0.0.1:3000 -> 8080
Forwarding from [::1]:3000 -> 8080
```

其中：



- service/<service name> 是 service 的名称（在当前的 YAML 文件中是 "my service"）。
- 3000 是你想在计算机上开启的端口。
- 80 是由 Service 在 port 字段中暴露的端口。



如果可以连接，说明设置正确。如果不能连接，很可能是标签弄错了或端口不匹配。



连接 Service 和 Ingress

**暴露应用程序的下一步是配置 Ingress。Ingress 必须知道如何检索 Service，然后连接 Pod 并将流量路由到它们**。Ingress 按名称和暴露的端口检索正确的 Service。

Ingress 和 Service 中必须匹配的有：

- Ingress 的 service.port 必须匹配 Service 的 port。
- Ingress 的 service.name 必须匹配 Service 的 name。

下图概括了如何连接这些 port：

![image-20210308093420220](/images/Deployment-Troubleshooting/depl12.png)
你已经知道了 Service 会暴露一个 port

![image-20210308093436054](/images/Deployment-Troubleshooting/depl13.png)

<center>Ingress 有一个字段叫做 ServicePort</center>

![image-20210308093450724](/images/Deployment-Troubleshooting/depl14.png)

<center>Service 的 port 和 Ingress 的 ServicePort 必须始终匹配</center>

![image-20210308093504837](/images/Deployment-Troubleshooting/depl15.png)

如果你要把端口 80 分配给一个 Service，必须把 ServicePort 也改成 80

实际操作中，你应该看看这几行：

```
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  ports:
    - port: 80
      targetPort: 8080
  selector:
    any-name: my-app
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
spec:
  rules:
  - http:
      paths:
      - backend:
          service:
            name: my-service
            port:
              number: 80
        path: /
        pathType: Prefix
```

如何测试 Ingress 是否正常运行？

你可以使用之前的策略，即 kubectl port-forward，但是要注意是连接到 Ingress controller 而不是 Service。

首先，使用以下命令为 Ingress controller 检索 Pod 名称：

```
kubectl get pods --all-namespaces
NAMESPACE   NAME                              READY STATUS
kube-system coredns-5644d7b6d9-jn7cq          1/1   Running
kube-system etcd-minikube                     1/1   Running
kube-system kube-apiserver-minikube           1/1   Running
kube-system kube-controller-manager-minikube  1/1   Running
kube-system kube-proxy-zvf2h                  1/1   Running
kube-system kube-scheduler-minikube           1/1   Running
kube-system nginx-ingress-controller-6fc5bcc  1/1   Running
```

验证 Ingress Pod（可能在另一个命名空间中），描述它来检索端口：

```
kubectl describe pod nginx-ingress-controller-6fc5bcc \
 --namespace kube-system \
 | grep Ports
Ports:         80/TCP, 443/TCP, 18080/TCP
```

最后，连接到 Pod：

```
kubectl port-forward nginx-ingress-controller-6fc5bcc 3000:80 --namespace kube-system
Forwarding from 127.0.0.1:3000 -> 80
Forwarding from [::1]:3000 -> 80
```

此时，你每次访问计算机上的端口 3000 时，请求都会转发到 Ingress controller Pod 的端口 80。

访问本地ip加3000端口即可

关于端口的总结

快速总结一下哪些端口和标签应该匹配：

- Service selector 应该和 Pod 的标签匹配；
- Service 的 targetPort 应该和 Pod 里面容器的 containerPort 匹配；
- Service 端口可以是任意数字。多个 Service 可以使用同一个端口，因为不同的 Service 分配的 IP 地址不同；
- Ingress 的 service.port 应该和 Service 的 port 匹配；
- Service 的名称应该和 Ingress 中 service.name 字段匹配。



了解如何构造 YAML 文件中的定义只是开始。出问题了怎么办？可能 Pod 无法启动了，或崩溃了。

3个步骤排查 kubernetes Deployment 故障

在深入探究有故障的 Deploymen 时，必须明确 Kubernetes 是如何工作的。**由于每个 Deployment 中都有三个组件，因此你应该从下往上依次调试所有组件。**



- 确保 Pod 正在运行；
- 着重关注让 Service 将流量路由到 Pod；
- 检查 Ingress 的配置是否正确。



![image-20210308093555054](/images/Deployment-Troubleshooting/depl16.png)

应该从最底层开始为 Deployment 做故障排查。首先，检查 Pod 是否已就绪并在运行中

![image-20210308093608665](/images/Deployment-Troubleshooting/depl17.png)

如果 Pod 已就绪，应该检查 Service 是否能将流量路由到 Pod

![image-20210308093621477](/images/Deployment-Troubleshooting/depl18.png)

最后，检查 Service 和 Ingress 之间的连接

**排查 Pod 故障**

**大多数情况下，问题出在 Pod 本身。你应该确保 Pod 已就绪并且在运行中。**那么如何检查呢？

```
kubectl get pods
NAME                    READY STATUS            RESTARTS  AGE
app1                    0/1   ImagePullBackOff  0         47h
app2                    0/1   Error             0         47h
app3-76f9fcd46b-xbv4k   1/1   Running           1         47h
```

在上面的输出中，最后一个 Pod 是就绪且在运行的，但是前两个 Pod 既没有就绪，也没有运行。你怎么检查哪里出了问题呢？

以下 4 个命令可以对 Pod 做故障排查：



- kubectl logs <pod name> 有助于检索 Pod 中容器的日志；
- kubectl describe pod <pod name> 对检索与 Pod 相关的事件列表很有用；
- kubectl get pod <pod name> 可提取 Kubernetes 中存储的 Pod 的 YAML 定义；
- kubectl exec -ti <pod name> bash 可在 Pod 中的一个容器运行一个交互式命令。



那么你该用哪个命令呢？具体情况具体分析，通常这些命令要结合起来用。



**常见的 Pod 报错**

Pod 可能会在启动和运行时出现错误。

启动时的错误包括：

- ImagePullBackoff
- ImageInspectError
- ErrImagePull
- ErrImageNeverPull
- RegistryUnavailable
- InvalidImageName

运行中的错误包括：

- CrashLoopBackOff
- RunContainerError
- KillContainerError
- VerifyNonRootError
- RunInitContainerError
- CreatePodSandboxError
- ConfigPodSandboxError
- KillPodSandboxError
- SetupNetworkError
- TeardownNetworkError

有些错误的频率很高。下面是最常见的错误以及解决方法。

**ImagePullBackOff**

当 Kubernetes 无法检索 Pod 中某一个容器的镜像时会报这个错。常见的原因如下：

- 镜像名称无效——比如，你拼错了镜像名称，或者镜像不存在。
- 为镜像指定了一个不存在的标签。
- 正在检索的镜像属于私有 registry，Kubernetes 没有访问的凭证。

前两种情况可以通过改正镜像名称/标签解决。对于最后一种情况，应该将私有 registry 的访问凭证通过 Secret 添加到 Kubernetes 中，并在 Pod 中引用它。

官方文档中有解决方法示例：https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/



**CrashLoopBackOff**

如果容器无法启动，Kubernetes 将显示 CrashloopBackOff 的信息。通常，在如下情况下容器无法启动：



- 应用程序中存在错误，阻止了容器的启动；
- 容器配置有误：StackOverFlow 上这个问题就是如此 https://stackoverflow.com/questions/41604499/my-kubernetes-pods-keep-crashing-with-crashloopbackoff-but-i-cant-find-any-lo
- Liveness 探针失败多次。



你应该尝试检索容器日志，查看为什么容器无法启动。如果你无法查看日志是因为容器重启得太快了，可以用如下命令：

```
kubectl logs <pod-name> --previous
```

这个命令将打印前一个容器的错误消息。

**RunContainerError**

当容器无法启动时会出现这个错误。它甚至会在容器里的应用程序启动之前出现。这个问题通常是由于如下错误配置造成的：



- 挂载不存在的卷，如 ConfigMap 或 Secret；
- 将只读卷挂载为读写卷。



可以使用 kubectl describe pod <pod-name> 命令检查和分析这个错误。



**Pod 处于 Pending 的状态**

当你创建了一个 Pod，这个 Pod 处于 Pending 的状态。为什么会这样？

假设你的调度器组件运行良好，原因可能有这些：

- 集群没有足够的资源（例如 CPU 和内存）来运行 Pod。
- 当前的命名空间具有 ResourceQuota 对象，创建 Pod 将使命名空间超过配额。
- 该 Pod 绑定了一个处于 Pending 状态的 PersistentVolumeClaim。



最好的选择是在 kubectl describe 命令中检查事件。

```
kubectl describe pod <pod name>
```

对于因 ResourceQuota 造成的错误，可以使用以下方法检查群集日志：

```
kubectl get events --sort-by=.metadata.creationTimestamp
```



**Pod 处于未就绪状态**

如果 Pod 正在运行但未就绪，则表示“就绪”探针失败。

当“就绪”探针失败时，则 Pod 未连接到服务，并且没有流量转发到该实例。

就绪探针故障是应用程序相关的错误，因此应该检查 kubectl describe 中的“事件”以验证错误。



**排查 Service 故障**

如果 Pod 在运行中且已就绪，但仍无法收到应用程序的响应，就应检查 Service 的配置是否正确。

Service 会根据 Pod 的标签将流量路由到 Pod。因此，应该先检查 Service 定位了多少个 Pod。

可以通过检查 Service 中的 Endpoint 来做到这一点：

```
kubectl describe service my-service
Name:                     my-service
Namespace:                default
Selector:                 app=my-app
IP:                       10.100.194.137
Port:                     <unset>  80/TCP
TargetPort:               8080/TCP
Endpoints:                172.17.0.5:8080
```

一个 Endpoint 是一对 <ip address:port> ，当 Service 定位到一个 Pod 后，至少应该有一个 Endpoint。



如果“Endpoint”部分为空，有两种解释：



- 正在运行的 Pod 没有正确的标签（应该检查一下是否在正确的命名空间中）；
- Service 的 selector 标签拼写有误。



如果能看到 Endpoint 列表，但仍然无法访问应用程序，则 service 中的 targetPort 可能出问题了。如何测试 Service 呢？无论什么类型的 Service，都可以用 kubectl port-forward 来连接：

```
kubectl port-forward service/<service-name> 3000:80
```

其中：



- <service-name> 是 Service 的名称；
- 3000 是你想在计算机上打开的端口；
- 80 是 Service 暴露的端口。

**排查 Ingress 故障**

如果已经到了这个阶段，那么意味着：

- Pod 在运行中且是就绪状态；
- Service 可以分发流量分配到 Pod。



但是你仍然看不到应用程序的响应。这很有可能是 Ingress 配置出错了。

因为 Ingress controller 是集群中的第三方组件，根据 Ingress controller 的类型有不同的调试技巧。但是在进入到 Ingress 专用工具之前，可以先做些简单的检查。

Ingress 使用 service.name 和 service.port 连接到 Service。应该检查一下这些配置是否正确。

可以用以下命令检查 Ingress 配置是否正确：

```
kubectl describe ingress my-ingress
Name:             my-ingress
Namespace:        default
Rules:
  Host        Path  Backends
  ----        ----  --------
  *
              /   my-service:80 (<error: endpoints "my-service" not found>)
```

如果 Backend 列为空，那么配置中肯定出现了错误。如果在 Backend 列能看到 Endpoint，但仍然无法访问应用程序，问题可能是：

- 将 Ingress 暴露到公网的方式；
- 将集群暴露到公网的方式；

可以通过直接连接到 Ingress pod 将基础设施问题和 Ingress 隔离开。

首先，为 Ingress controller （可能在其他的命名空间中）检索 Pod：

```
kubectl get pods --all-namespaces
NAMESPACE   NAME                              READY STATUS
kube-system coredns-5644d7b6d9-jn7cq          1/1   Running
kube-system etcd-minikube                     1/1   Running
kube-system kube-apiserver-minikube           1/1   Running
kube-system kube-controller-manager-minikube  1/1   Running
kube-system kube-proxy-zvf2h                  1/1   Running
kube-system kube-scheduler-minikube           1/1   Running
kube-system nginx-ingress-controller-6fc5bcc  1/1   Running
```

描述它来检索端口：

```
kubectl describe pod nginx-ingress-controller-6fc5bcc
 --namespace kube-system \
 | grep Ports
    Ports:         80/TCP, 443/TCP, 8443/TCP
    Host Ports:    80/TCP, 443/TCP, 0/TCP
```

最后，连接到 Pod：

```
kubectl port-forward nginx-ingress-controller-6fc5bcc 3000:80 --namespace kube-system
Forwarding from 127.0.0.1:3000 -> 80
Forwarding from [::1]:3000 -> 80
```

到这一步，每次你访问计算机上端口 3000，请求都会转发到 Pod 中的端口 80。

现在问题解决了吗？



- 如果解决了，那么就是基础设施问题。你要看一下流量是如何路由到集群的。
- 如果没有解决，那么是 Ingress controller 的问题，你应该调试 controller。

如果还是不能让 Ingress controller 正常，应该开始调试它。

Ingress Controller 有很多版本，使用较多的包括 Nginx，HAProxy，Traefik 等。查阅一下你使用的 Ingress Controller 的文档，找到故障排除指南。

因为 Ingress Nginx （https://github.com/kubernetes/ingress-nginx）是最流行的 Ingress Controller，因此我们在下一节介绍一些技巧。

**调试 Ingress Nginx**

Ingress-nginx 项目有一个针对 Kubectl 的官方插件：https://kubernetes.github.io/ingress-nginx/kubectl-plugin/

你可以使用 kubectl ingress-nginx 来进行如下操作：



- 检查日志、Backend、证书等；
- 连接到 Ingress；
- 检查当前配置。



可以尝试以下三个命令：



- kubectl ingress-nginx lint ：用于检查 nginx.conf;
- kubectl ingress-nginx backend：用于检查 Backend（类似 kubectl describe ingress <ingress-name>）；
- kubectl ingress-nginx logs：用于检查日志。



请注意，你可能需要使用 --namespace为 Ingress controller 指定正确的命名空间。



**总结**

如果你不知从何下手，那么在 Kubernetes 中进行故障排查可能会是一项艰巨的任务。始终记得从下往上解决问题：从 Pod 开始，然后到 Service 和 Ingress。

本文中的调试技巧也适用于其他地方，比如：

- 出现故障的 Job 和 CronJob；
- StatefulSet 和 DaemonSet。