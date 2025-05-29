# Condor - 实用命令行工具集

Condor 是一个功能丰富的命令行工具集，专注于提升开发效率和系统管理体验。它集成了文件整理、系统监控、应用管理和Flutter开发辅助等多种实用功能，让日常操作更高效。

## 功能一览

Condor是一个强大的命令行工具集，提供多种实用功能：

| 类别 | 命令 | 描述 |
|------|------|------|
| **系统工具** | `apps` | 查询和管理Mac系统中安装的应用程序 |
| | `sysmon` | 实时监控CPU、内存和网络使用情况 |
| | `fileorg` | 智能文件整理器，按类型和日期分类整理文件 |
| | `iptest` | 检测当前IP或指定IP的网络质量和地理位置信息 |
| **AI工具** | `ai chat` | 在终端中与OpenAI、Claude或Grok模型对话 |
| | `ai config` | 配置AI设置，管理API源和默认模型 |
| | `copilot freedom` | 解除Copilot Claude 3.7使用限制 |
| **开发工具** | `flutter version` | 查询和管理Flutter版本 |
| | `optimize-build` | 优化Flutter项目iOS端编译速度 |
| | `optimize-build xctoolchain-copy` | 复制Xcode工具链以优化编译 |
| | `optimize-build redirect-cc` | 重定向编译器以提升性能 |
| **符号表工具** | `init` | 初始化符号表配置 |
| | `upload` | 上传符号表到Bugly等服务 |

## ☕ 请我喝一杯咖啡

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/T6T4JKVRP) [![wechat](https://img.shields.io/static/v1?label=WeChat&message=微信收款码&color=brightgreen&style=for-the-badge&logo=WeChat)](https://cdn.jsdelivr.net/gh/FullStackAction/PicBed@resource20220417121922/image/202303181116760.jpeg)

微信技术交流群请看: [【微信群说明】](https://mp.weixin.qq.com/s/JBbMstn0qW6M71hh-BRKzw)

## 安装

### Homebrew

```shell
brew install LinXunFeng/tap/condor
```

<!--

首次安装

```shell
brew tap LinXunFeng/tap && brew install condor
```

更新
```shell
brew update && brew reinstall condor
```
-->

### Pub Global

```shell
dart pub global activate condor_cli
```

## 快速开始

安装完成后，查看可用命令列表：

```shell
condor help
```

查看特定命令的使用帮助：

```shell
condor help fileorg
```

常用命令示例：

```shell
# 整理下载文件夹
condor fileorg

# 监控系统资源
condor sysmon

# 查看已安装应用
condor apps

# 检测当前IP质量
condor iptest
```

## 使用

### AI对话与配置

在终端中与AI模型进行交互，支持OpenAI、Claude和Grok等大型语言模型，支持配置多个API源。

#### 配置AI设置

```shell
# 列出当前配置
condor-ai config -l

# 列出特定模型的所有API源
condor-ai config --list-sources --source=openai:default

# 添加API源
condor-ai config --source=openai:default --key="sk-xxxxxxxxxx"

# 添加自定义源
condor-ai config --source=openai:custom --key="sk-xxxxxxxxxx" --endpoint="https://api.自定义域名.com/v1"

# 添加Grok源
condor-ai config --source=grok:xai --key="sk-xxxxxxxxxx" --endpoint="https://api.xai.com/v1"

# 扫描源支持的模型
condor-ai config --scan-models-source=openai:default

# 一步完成源配置并扫描模型
condor-ai config --source=openai:default --key="sk-xxxxxxxxxx" --scan-models

# 设置默认模型
condor-ai config -m openai

# 更改特定模型
condor-ai config --openai-model="gpt-4o"
condor-ai config --claude-model="claude-3-opus-20240229"
condor-ai config --grok-model="grok-1"

# 重置配置
condor-ai config -r
```

|参数|别名|描述|
|-|-|-|
|`model`|`m`|设置默认AI模型(openai,claude,grok)|
|`source`|-|为指定模型添加/选择API源 (格式: [model]:[source_name])|
|`use-source`|-|设置模型使用的API源 (格式: [model]:[source_name])|
|`endpoint`|-|设置API源端点URL (与--source一起使用)|
|`key`|-|设置API源密钥 (与--source一起使用)|
|`openai-model`|-|设置OpenAI模型|
|`claude-model`|-|设置Claude模型|
|`grok-model`|-|设置Grok模型|
|`list`|`l`|列出当前配置|
|`list-sources`|-|列出指定模型的所有API源|
|`scan-models`|-|扫描当前活跃源支持的模型|
|`scan-models-source`|-|扫描指定源支持的模型 (格式: [model]:[source_name])|
|`add-all-models`|-|添加扫描到的所有模型到配置中|
|`delete-source`|-|删除指定的API源|
|`reset`|`r`|重置所有配置|

例如: `condor-ai config --list-sources --source=openai:default`

#### 与AI聊天

```shell
# 开始新对话(使用默认模型)
condor-ai chat

# 使用指定模型
condor-ai chat -m grok

# 设置系统提示
condor-ai chat -s "你是一位专业的Dart编程助手"

# 列出历史对话
condor-ai chat -l

# 加载历史对话
condor-ai chat --load=1718170036521
```

|参数|别名|描述|
|-|-|-|
|`model`|`m`|使用的AI模型(openai,claude,grok)|
|`system`|`s`|设置系统提示|
|`stream`|-|使用流式响应(默认开启)|
|`new`|`n`|开始新对话|
|`list`|`l`|列出历史对话|
|`load`|-|加载指定的历史对话|

在聊天过程中，可使用以下命令：
- 输入 `exit` 或 `quit` 退出对话
- 输入 `clear` 清除当前对话历史

### Mac应用管理

查询和管理Mac系统中安装的应用程序，包括App Store、Homebrew安装的应用以及其他常见应用。

```shell
# 列出所有应用
condor apps

# 显示应用详细信息
condor apps -d

# 查看特定应用详情
condor apps --app "Chrome"

# 显示通过Homebrew安装的应用
condor apps --homebrew

# 显示通过Mac App Store安装的应用
condor apps --mas

# 检查应用更新
condor apps -o
```

|参数|别名|描述|
|-|-|-|
|`count`|`c`|只显示应用数量|
|`all`|`a`|包含系统应用|
|`search`|`s`|搜索特定应用|
|`homebrew`|-|显示通过Homebrew安装的应用|
|`mas`|-|显示通过Mac App Store安装的应用|
|`detailed`|`d`|显示应用详细信息|
|`app`|-|查看指定应用的详细信息|
|`outdated`|`o`|检查哪些应用有可用更新|

### 系统监控

实时监控CPU、内存和网络使用情况，帮助分析系统性能和资源占用。

```shell
# 监控所有资源
condor sysmon

# 只监控CPU
condor sysmon -c

# 只监控内存
condor sysmon -m

# 只监控网络
condor sysmon -n

# 显示资源占用前5的进程
condor sysmon -t

# 调整刷新间隔为3秒
condor sysmon -r 3
```

|参数|别名|描述|
|-|-|-|
|`cpu`|`c`|只监控CPU使用情况|
|`memory`|`m`|只监控内存使用情况|
|`network`|`n`|只监控网络使用情况|
|`refresh`|`r`|刷新间隔，单位秒（默认1秒）|
|`top`|`t`|显示资源占用前5的进程|

### 文件整理器

智能分析并整理下载文件夹，按文件类型和日期分类，让文件管理更轻松。

```shell
# 使用默认配置整理下载文件夹
condor fileorg

# 指定源文件夹和目标文件夹
condor fileorg -s ~/Downloads -t ~/OrganizedFiles

# 预览模式，不实际移动文件
condor fileorg -d

# 递归处理子文件夹
condor fileorg -r

# 交互模式，处理每个文件前询问
condor fileorg -i

# 排除特定文件或文件夹
condor fileorg -e "node_modules,temp,cache"
```

|参数|别名|描述|默认值|
|-|-|-|-|
|`source`|`s`|要整理的源文件夹路径|`~/Downloads`|
|`target`|`t`|整理后的目标文件夹路径|`源文件夹/已整理`|
|`dryrun`|`d`|预览模式，不实际移动文件|-|
|`recursive`|`r`|递归处理子文件夹|-|
|`byType`|-|按文件类型分类|`true`|
|`byDate`|-|按文件修改日期分类（年/月）|`true`|
|`exclude`|`e`|排除的文件或文件夹名称，用逗号分隔|-|
|`interactive`|`i`|交互模式，处理每个文件前询问|-|

### IP质量检测

检测当前IP或指定IP的质量，包括地理位置、网络提供商、威胁评估和信任度评分等信息。

```shell
# 检测本机IP
condor iptest

# 检测指定IP
condor iptest -i 8.8.8.8

# 显示原始JSON响应
condor iptest --raw

# 使用浏览器User-Agent
condor iptest --browser

# 显示调试信息
condor iptest --debug

# 通过代理检测
condor iptest --proxy 127.0.0.1:7890
```

|参数|别名|描述|
|-|-|-|
|`ip`|`i`|要检测的IP地址，不提供则检测本机IP|
|`raw`|`r`|显示原始JSON响应|
|`browser`|`b`|使用浏览器User-Agent|
|`debug`|`d`|显示调试信息，包括请求和响应详情|
|`proxy`|`p`|使用指定的HTTP代理 (例如: 127.0.0.1:7890)|

也可以使用以下别名快速调用:

```shell
# 基本检测
condor-iptest

# 显示原始JSON响应
condor-iptest-raw

# 使用浏览器User-Agent
condor-iptest-browser

# 显示调试信息
condor-iptest-debug
```

#### 故障排除

如果遇到网络相关问题，可以参考以下建议进行故障排除：

1. **代理连接错误** 
2. clash 7890
3. clash verge 7897

   当使用`--proxy`选项时，如果出现类似以下错误：
   
   ```
   检测IP质量时出错: SocketException: Connection refused (OS Error: Connection refused, errno = 61), address = 127.0.0.1, port = XXXXX
   ```
   
   可能是因为：
   - 指定的代理服务器未启动或不可用
   - 代理地址或端口不正确
   - 本地代理服务需要身份验证
   
   解决方法：
   - 确认代理服务器已启动（例如V2Ray、Clash等）
   - 验证代理地址和端口是否正确
   - 尝试在浏览器中使用相同代理设置

4. **网络连接问题**

   如果连接API失败，可以使用`--debug`参数查看详细的网络请求信息，帮助诊断问题。
   
5. **IP地址不一致**

   如果通过浏览器直接访问API和通过命令行访问显示的IP不同，这通常是因为：
   - 浏览器可能使用了系统代理或VPN
   - 不同的网络路径可能导致不同的出口IP
   
   解决方法：
   - 使用`--browser`选项模拟浏览器请求
   - 使用`--proxy`选项指定与浏览器相同的代理设置

### Copilot - 解除限制

> 文章：[AI - RooCode 解限使用 Copilot Claude 3.7](https://mp.weixin.qq.com/s/MPgDkJ37s9X7DzAvS4azwQ)

在 `Cline` 和 `RooCode` 中使用 `VS Code LM API` + `copilot - claude-3.7.sonnet` 时，会出现如下错误

```
Request Failed: 400 {"error":{"message":"Model is not supported for this request.","param":"model","code":"model_not_supported","type":"invalid_request_error"}}

Retry attempt 1
Retrying in 5 seconds...
```

限制的情况，此时可以通过 `condor` 来解除限制

```shell
condor copilot freedom
```

杀掉并重启 `VS Code` 即可


### 符号表

<details>

<summary>符号表配置初始化与上传</summary>

#### 初始化

输出配置文件到指定目录

```shell
condor init -o ~/Downloads/condor
```

如有些配置是固定的，可以通过 `-r` 参数指定一个配置文件的路径，这样会将固定的配置写入到输出的配置文件中进行覆盖

```shell
condor init -o ~/Downloads/condor -r ~/Downloads/condor/config2.yaml
```

|参数|别名|描述|
|-|-|-|
|`ref`|`r`|指定固定配置文件的路径|
|`out`|`o`|指定配置文件的输出目录路径|
|`symbolZipPath`|-|符号表压缩包路|
|`bundleId`|-|`app` 的 `bundleId`|
|`version`|-|`app` 的版本|
|`flutterVersion`|-|`Flutter` 版本|
|`buglyAppId`|-|`bugly` 的 `appid`|
|`buglyAppKey`|-|`bugly` 的 `appkey`|
|`buglyJarPath`|-|`buglyqq-upload-symbol.jar` 的路径|


#### 上传符号表

> 针对 `fastlane` 打出来的符号表压缩包

通过指定最后的配置文件的路径来上传符号表

```shell
condor upload -c ~/Downloads/condor/config.yaml
```

</details>

### Flutter

输出当前的 `flutter` 版本

```shell
# 输出
# 3.13.9
condor flutter version print
```

```shell
# 输出 fvm 指定的 flutter 的版本
# 3.7.12
condor flutter version print -f 'fvm spawn 3.7.12'
```

在 `jenkins` 中使用

> 以 `FLUTTER_VERSION` 环境变量来记录当前的 `flutter` 版本供全局使用

```groovy
environment {
  FLUTTER_VERSION = sh(script: "condor flutter version print -f 'fvm spawn ${flutter_version}'", returnStdout: true).trim()
}
```

### 优化 `Flutter` 项目 `ios` 端的编译速度

> 文章：[Flutter - iOS编译加速](https://mp.weixin.qq.com/s/iyvoAMCvC8WKN-zWsQcU_w)

依赖 [Rugby](https://github.com/swiftyfinch/Rugby) 实现，所以需要先安装 `Rugby`

```shell
curl -Ls https://swiftyfinch.github.io/rugby/install.sh | bash
```

在你的终端配置(如: `~/.zshrc`)中添加如下配置

```shell
export PATH=$PATH:~/.rugby/clt
```

在 `pod install` 完成后执行如下命令进行优化

```shell
condor optimize-build --config path/to/rugby/plans.yml
```

指定 `flutter` 版本

```shell
condor optimize-build \
  --config path/to/rugby/plans.yml \
  --flutter "fvm spawn 3.24.5"
```

指定编译模式

通过 `--mode` 指定，或者设置环境变量 `export CONDOR_BUILD_MODE=release`

```shell
condor optimize-build \
  --config path/to/rugby/plans.yml \
  --mode release
```

### 使用 `Xcode 15` 的工具链优化 `Xcode 16` 的编译

> 文章：[Flutter - Xcode16 还原编译速度](https://mp.weixin.qq.com/s/sVouMFVe-eXoCFEofriasw)

请先安装 `Xcode 16` 以下的版本，如: `Xcode 15.4.0`，建议使用 [XcodesApp](https://github.com/XcodesOrg/XcodesApp) 进行安装

安装完成后，把对应的 `Xcode` 名字记下，如 `/Applications/Xcode-15.4.0.app`，则取 `Xcode-15.4.0`，给下面的命令使用。

#### 拷贝 `xctoolchain`

```shell
condor optimize-build xctoolchain-copy --xcode Xcode-15.4.0
```

#### 重定向 `cc`

这一步会对 `flutter_tools` 源码进行修改，使其具备重定向 `cc` 的能力而已，在有配置 `CONDOR_TOOLCHAINS` 环境变量时才会生效，否则则使用默认的 `cc`。

```shell
# 使用默认 flutter，则不需要传 flutter 参数
condor optimize-build redirect-cc

# 如果你想指定 fvm 下的指定 Flutter 版本
condor optimize-build redirect-cc --flutter fvm spawn 3.24.5
```

设置环境变量 `CONDOR_TOOLCHAINS`，值为上述的 `Xcode` 名。

```shell
export CONDOR_TOOLCHAINS=Xcode-15.4.0
```
