# 域名监控服务 (Domain Monitor)

一个自动监控域名注册状态的 Python 脚本，支持 Telegram Bot 通知，帮助你及时获知心仪域名的可注册状态。

## 功能特点

- 🔍 **自动检测**：定期检查域名的注册状态
- 📱 **即时通知**：通过 Telegram Bot 发送详细通知
- 📊 **状态追踪**：记录每个域名的检查历史
- ⏰ **到期提醒**：域名即将到期时自动提醒
- 🛠️ **易于管理**：提供简单的命令行管理工具
- 📝 **详细日志**：完整的运行日志记录

## 通知内容

当域名可以注册时，你将收到包含以下信息的通知：
- 域名名称和当前状态
- 检测时间
- 推荐的域名注册商列表
- 注册建议（如注册年限、隐私保护等）
- 紧急行动提醒

## 系统要求

- Ubuntu/Debian Linux (推荐 Ubuntu 20.04+)
- Python 3.6+
- 稳定的网络连接
- Telegram Bot Token 和 Chat ID

## 快速开始

### 1. 创建 Telegram Bot

1. 在 Telegram 中找到 @BotFather
2. 发送 `/newbot` 创建新机器人
3. 设置机器人名称和用户名
4. 获取 Bot Token
5. 获取你的 Chat ID（可以使用 @userinfobot）

### 2. 部署到 VPS

```bash
# 1. 上传文件到 VPS
scp domain_monitor.py deploy.sh config.env root@your-vps-ip:/tmp/

# 2. 登录到 VPS
ssh root@your-vps-ip

# 3. 运行部署脚本
cd /tmp
chmod +x deploy.sh
./deploy.sh

# 4. 配置 Telegram
cd /opt/domain-monitor
nano config.env
# 填入你的 TELEGRAM_BOT_TOKEN 和 TELEGRAM_CHAT_ID

# 5. 添加要监控的域名
./manage.sh add example.com "我想要的域名"
./manage.sh add another-domain.net "备用域名"

# 6. 重启服务
sudo supervisorctl restart domain-monitor
```

## 使用方法

### 添加域名监控
```bash
cd /opt/domain-monitor
./manage.sh add domain.com "备注信息"
```

### 移除域名监控
```bash
./manage.sh remove domain.com
```

### 查看监控列表
```bash
./manage.sh list
```

### 立即检查所有域名
```bash
./manage.sh check
```

### 查看服务状态
```bash
sudo supervisorctl status domain-monitor
```

### 查看日志
```bash
# 查看服务日志
tail -f /var/log/domain-monitor.log

# 查看应用日志
tail -f /opt/domain-monitor/domain_monitor.log
```

## 配置说明

编辑 `config.env` 文件：

```bash
# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_CHAT_ID=987654321

# 检查间隔（分钟）
CHECK_INTERVAL_MINUTES=60  # 每小时检查一次
```

## 高级配置

### 修改检查间隔

默认每 60 分钟检查一次，可以根据需要调整：
- 高优先级域名：15-30 分钟
- 普通域名：60-120 分钟
- 低优先级：180-360 分钟

注意：过于频繁的检查可能被视为滥用。

### 批量添加域名

创建一个域名列表文件 `domains.txt`：
```
example1.com
example2.net
example3.org
```

然后批量添加：
```bash
while read domain; do
    ./manage.sh add "$domain"
done < domains.txt
```

## 故障排除

### 服务无法启动
```bash
# 检查错误日志
sudo journalctl -u supervisor -n 50

# 手动测试脚本
cd /opt/domain-monitor
source venv/bin/activate
python domain_monitor.py
```

### Telegram 通知不工作
1. 确认 Bot Token 正确
2. 确认 Chat ID 正确
3. 确保已经给 Bot 发送过消息
4. 检查网络连接

### WHOIS 查询失败
某些域名后缀可能不支持 WHOIS 查询，脚本会自动降级到 DNS 查询。

## 安全建议

1. **保护配置文件**：
   ```bash
   chmod 600 /opt/domain-monitor/config.env
   ```

2. **使用非 root 用户运行**

3. **定期更新系统**：
   ```bash
   sudo apt update && sudo apt upgrade
   ```

4. **设置防火墙**（如果需要）

## 维护

### 备份配置
```bash
cd /opt/domain-monitor
tar -czf domain-monitor-backup-$(date +%Y%m%d).tar.gz config.env domains.json
```

### 更新脚本
```bash
cd /opt/domain-monitor
# 备份当前版本
cp domain_monitor.py domain_monitor.py.bak
# 上传新版本
# ...
sudo supervisorctl restart domain-monitor
```

## 关于监控安全性

### 域名所有者能发现监控吗？

**简短回答：不会被发现。**

详细说明：

1. **WHOIS 查询是匿名的**
   - WHOIS 查询是公开服务，任何人都可以查询
   - 查询请求不会留下你的个人信息
   - 域名所有者无法知道谁查询了他们的域名

2. **DNS 查询更加隐蔽**
   - DNS 查询经过多级服务器
   - 最终的权威 DNS 服务器只能看到递归 DNS 服务器的 IP
   - 无法追踪到具体的查询者

3. **VPS 增加了额外的隐私层**
   - 查询来自 VPS 的 IP 地址
   - 不会暴露你的真实位置或身份

4. **合理的查询频率**
   - 默认 60 分钟查询一次，非常保守
   - 不会触发任何反爬虫或限流机制
   - 相比人工查询，自动化查询反而更不引人注意

### 额外的隐私保护建议

1. **使用不同的 WHOIS 服务器**
   ```python
   # 可以在代码中轮换使用不同的 WHOIS 服务器
   ```

2. **添加随机延迟**
   - 查询时间略微随机化（±5-10分钟）
   - 避免固定模式

3. **使用代理（如需要）**
   - 可以配置 VPS 使用代理服务器
   - 进一步隐藏查询来源

4. **分散查询**
   - 如果监控大量域名，可以分散到多个 VPS
   - 每个 VPS 负责一部分域名

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！

## 免责声明

本工具仅供学习和个人使用，请遵守相关法律法规和网站服务条款。
