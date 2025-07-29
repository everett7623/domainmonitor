# Domain Monitor (域名监控器)

一个简单而强大的 Python 脚本，用于自动监控域名注册状态，并通过 Telegram Bot 发送即时通知，帮助你及时捕获心仪的域名。

[![Python](https://img.shields.io/badge/Python-3.7+-blue.svg)](https://www.python.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

## ✨ 功能特点

- 🔍 **自动检测**：通过 Cron 定时任务，定期检查域名的 `whois` 信息。
- 📱 **即时通知**：当域名变为可注册状态时，立即通过 Telegram Bot 发送详细通知。
- 📊 **状态追踪**：在 `history.log` 中记录每个域名的历史检查状态。
- ⏰ **到期提醒**：当已注册的域名即将到期时（30天内），自动发送续费提醒。
- 🛠️ **易于管理**：提供一个简单的命令行管理工具 `manage.sh`，轻松增删域名和修改配置。
- 📝 **详细日志**：在 `run.log` 中记录完整的脚本运行日志，便于排查问题。

## 🚀 一键安装

在你的 Linux 服务器或设备上，只需运行以下命令即可完成所有安装和配置：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/everett7623/domainmonitor/main/install.sh)
```

安装脚本会自动处理依赖安装、文件配置和定时任务设置。

## 🔔 通知内容

当监控到心仪的域名可以注册时，你将收到一条这样的 Telegram 通知：

> 🚨 **域名可注册提醒** 🚨
>
> *域名名称*: `example.com`
> *当前状态*: ✅ *可以注册!*
> *检测时间*: 2025-07-29 10:00:00
>
> --- *注册建议* ---
> 🔹 *推荐注册商*:
>   - NameSilo (隐私保护免费)
>   - GoDaddy (全球最大)
>   - Cloudflare (成本价)
> 🔹 *注册年限*: 建议注册多年以锁定价格并利于SEO。
> 🔹 *隐私保护*: 强烈建议开启Whois隐私保护，防止垃圾邮件。
>
> ❗️ *紧急行动提醒*: 好域名非常抢手，请立即行动！


## ⚙️ 使用与管理

安装完成后，你可以通过 `manage.sh` 脚本来管理你的监控服务。

1.  进入项目目录：
    ```bash
    cd ~/domainmonitor
    ```
2.  运行管理脚本：
    ```bash
    ./manage.sh
    ```

你会看到一个清晰的菜单，可以进行以下操作：
- 添加监控域名
- 删除监控域名
- 查看监控域名列表
- 更新 Telegram Bot 配置
- 卸载整个脚本

## 📄 日志文件

所有日志文件都位于 `~/domainmonitor` 目录下：
- `run.log`: 脚本每次运行的详细输出，用于调试。
- `history.log`: 域名的状态变更历史，方便追踪。
- `cron.log`: 定时任务的执行日志。

## 🤝 贡献

欢迎提交 PR 或 Issue 来改进这个项目。

## 📄 许可证

本项目基于 [MIT License](LICENSE) 开源。
