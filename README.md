个人自用 团子大家族哦~

# 修改
### daed
使用 olicesx/dae 的daed 有流量统计功能
https://github.com/darkrain88/daed-immWRT-CI

## ebpf
[开启内核eBPF(tb)](https://github.com/GHNERCH/OpenWRT-CI)

最后同步: Fix formatting and improve README content GHNERCH* 2026/8/17 15:32

## daed ???
固件内置 [kenzok8/openwrt-daede](https://github.com/kenzok8/openwrt-daede) `main` 分支的
`daed` 和 `luci-app-daede`，使用带流量统计的新版核心。

## doona / honk

固件新增 `honk`、`luci-app-honk` 和中文翻译，使用
[daeuniverse/openwrt-packages](https://github.com/daeuniverse/openwrt-packages)
的最新官方源码构建配方。每次编译自动选择 honk 和
[doona](https://github.com/Zakkaus/doona) 的最新已发布版本，包含 alpha、beta、rc
预发布版，排除 Debug 构建；分别按版本号选择，不再固定版本。新版 doona 的标准版和
lite 版内嵌到 honk，下载仍校验发布包的 SHA-256。Rust stable/nightly 工具链与
eBPF 链接器继续使用本次 honk 源码要求的版本，并校验链接器的 SHA-256。

每次构建解析一次版本，实际 tag、提交及面板校验值记录在构建报告
`honk-versions.json` 中。GitHub API 使用工作流已有的 `GITHUB_TOKEN`；遇到限流时
改读公开发布订阅源。版本解析或校验失败会停止构建，不会退回旧版本。
前后端分别跟随最新发布版，新功能仍取决于该次 honk 的 API 支持。

全新安装时，daed 和 honk 都默认关闭，由用户在 LuCI 中选择启用其中一个。
使用 honk 时，在 LuCI「服务 → honk」编辑配置并启用，初始路由为全部直连。
切换前先停止另一套代理，避免同时接管网络。保留配置升级时沿用已有的启用状态。
启用后访问 `http://192.168.2.1:9090/ui/`，首次访问创建管理员，再添加订阅、
节点和路由规则。面板仅监听构建参数 `WRT_IP` 对应的 LAN 地址；修改 LAN IP
时，也需要修改 `/etc/honk/config.dae` 中的 `listen`。

默认配置在 [Config/honk.dae](Config/honk.dae)。管理员、订阅等状态保存在
`/etc/honk/data`，整个 `/etc/honk/` 已加入软件包的配置备份清单，普通保留配置
的 sysupgrade 会保留这些数据。构建配方在 `.github/scripts/prepare-honk.sh`，
仅导入 honk 及其 LuCI 组件，沿用本固件的内核 BTF 和 geodata 软件包。

参考：[doona OpenWrt 安装文档](https://doona.daeuniverse.org/zh-CN/install-openwrt.html)、
[honk OpenWrt 教程](https://www.qichiyu.com/1151.html)。

# ------------------------- end -------------------------

# 高质量<免费>交流群

[IPQ技术讨论群](https://qm.qq.com/q/v7nMhzB4oU)

# 本地编译器
https://github.com/VIKINGYFY/OWRT-Tools.git

# 自用修改版插件
https://github.com/VIKINGYFY/packages.git

# OpenWRT-CI
官方版：
https://github.com/immortalwrt/immortalwrt.git

自用版：
https://github.com/VIKINGYFY/immortalwrt.git

# 固件简要说明
固件信息里的时间为编译开始的时间，方便核对上游源码提交时间。

MEDIATEK系列、QUALCOMMAX系列、ROCKCHIP系列、X86系列。

# 目录简要说明
workflows——自定义CI配置

Scripts——自定义脚本

Config——自定义配置

## Star History

<a href="https://www.star-history.com/?repos=vikingyfy%2Fopenwrt-ci&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&legend=top-left" />
 </picture>
</a>
