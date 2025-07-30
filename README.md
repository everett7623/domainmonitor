# Domain Monitor 域名监控系统

<div align="center">

![Domain Monitor](https://img.shields.io/badge/Domain-Monitor-blue?style=for-the-badge)
![Python](https://img.shields.io/badge/Python-3.7+-green?style=for-the-badge&logo=python)
![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)

**自动监控域名注册状态，第一时间通知您心仪域名的可用情况**

</div>

## 🚀 一键安装

```bash
bash <(curl -sSL https://raw.githubusercontent.com/everett7623/domainmonitor/main/install.sh)
```

## ✨ 功能特点

- 🔍 **自动检测**：定期检查域名的注册状态
- 📱 **即时通知**：通过 Telegram Bot 发送详细通知
- 📊 **状态追踪**：记录每个域名的检查历史
- ⏰ **到期提醒**：域名即将到期时自动提醒
- 🛠️ **易于管理**：提供简单的命令行管理工具
- 📝 **详细日志**：完整的运行日志记录

## 📬 通知内容

当域名状态发生变化时，您将收到包含以下信息的通知：

- 域名名称和当前状态
- 检测时间
- 推荐的域名注册商列表
- 注册建议（如注册年限、隐私保护等）
- 紧急行动提醒

## 💻 系统要求

- Python 3.7 或更高版本
- Linux/macOS/Windows
- 网络连接
- Telegram Bot Token（可选）

## 📖 使用说明

### 1. 安装
运行一键安装脚本，按照提示操作即可。

### 2. 管理菜单
安装完成后，运行 `domainmonitor` 命令进入管理菜单：

- **添加监控域名**：添加新的域名到监控列表
- **删除监控域名**：从监控列表中移除域名
- **添加Telegram Bot通知**：配置 Telegram 通知
- **删除Telegram Bot通知**：移除 Telegram 通知配置
- **查看监控域名**：显示当前监控的所有域名
- **删除监控域名和脚本**：完全卸载系统
- **退出**：退出管理菜单

### 3. Telegram Bot 配置

1. 在 Telegram 中搜索 [@BotFather](https://t.me/botfather)
2. 发送 `/newbot` 创建新的 Bot
3. 按照提示设置 Bot 名称和用户名
4. 获取 Bot Token
5. 启动您的 Bot 并发送任意消息
6. 在管理菜单中添加 Bot Token 和您的 Chat ID

## 🔧 高级配置

配置文件位于 `~/.domainmonitor/config.json`，可以手动编辑：

```json
{
    "domains": ["example.com", "test.org"],
    "telegram": {
        "bot_token": "YOUR_BOT_TOKEN",
        "chat_id": "YOUR_CHAT_ID"
    },
    "check_interval": 3600,
    "log_level": "INFO"
}
```

## 📝 日志文件

日志文件保存在 `~/.domainmonitor/logs/` 目录下：
- `domainmonitor.log`：主程序日志
- `check_history.log`：域名检查历史记录

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

## 👨‍💻 作者

- GitHub: [@everett7623](https://github.com/everett7623)

## ⭐ 如果觉得有用，请给个 Star！

---

<div align="center">
Made with ❤️ by everett7623
</div>
