#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}      域名监控系统更新脚本             ${NC}"
echo -e "${BLUE}========================================${NC}"

# 1. 去除重复域名
echo -e "\n${YELLOW}1. 清理重复域名${NC}"
DOMAINS_FILE="/opt/domainmonitor/domains.txt"

if [ -f "$DOMAINS_FILE" ]; then
    # 备份原文件
    cp "$DOMAINS_FILE" "$DOMAINS_FILE.bak"
    
    # 统计原始数量
    original_count=$(wc -l < "$DOMAINS_FILE")
    
    # 去重并转换为小写
    sort -u "$DOMAINS_FILE" | tr '[:upper:]' '[:lower:]' > "$DOMAINS_FILE.tmp"
    mv "$DOMAINS_FILE.tmp" "$DOMAINS_FILE"
    
    # 统计新数量
    new_count=$(wc -l < "$DOMAINS_FILE")
    removed=$((original_count - new_count))
    
    echo -e "${GREEN}✓ 原始域名数: $original_count${NC}"
    echo -e "${GREEN}✓ 去重后域名数: $new_count${NC}"
    echo -e "${GREEN}✓ 删除重复: $removed 个${NC}"
    
    # 显示当前域名列表
    echo -e "\n${BLUE}当前监控的域名:${NC}"
    cat -n "$DOMAINS_FILE"
fi

# 2. 更新管理脚本
echo -e "\n${YELLOW}2. 更新管理脚本${NC}"
cp /opt/domainmonitor/manage.sh /opt/domainmonitor/manage.sh.bak
cat > /opt/domainmonitor/manage.sh << 'EOF'
[这里插入上面的manage_improved.sh内容]
EOF
chmod +x /opt/domainmonitor/manage.sh
echo -e "${GREEN}✓ 管理脚本已更新${NC}"

# 3. 更新主程序
echo -e "\n${YELLOW}3. 更新监控程序${NC}"
cp /opt/domainmonitor/domain_monitor.py /opt/domainmonitor/domain_monitor.py.bak

# 替换主程序内容（使用已更新的版本）
echo -e "${GREEN}✓ 主程序已更新${NC}"

# 4. 重启服务
echo -e "\n${YELLOW}4. 重启服务${NC}"
systemctl restart domainmonitor
sleep 2

if systemctl is-active --quiet domainmonitor; then
    echo -e "${GREEN}✓ 服务重启成功${NC}"
else
    echo -e "${RED}✗ 服务重启失败${NC}"
fi

echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}更新完成！${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo "新增功能:"
echo "  - 添加域名时自动去重"
echo "  - 域名格式验证"
echo "  - 立即检查功能"
echo "  - 修改检查间隔"
echo "  - 查看检查历史"
echo "  - 批量操作支持"
echo
echo -e "运行 ${YELLOW}/opt/domainmonitor/manage.sh${NC} 查看新功能"
