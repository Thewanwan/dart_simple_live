import os
import json
import re

# --- 路径配置 ---
# 1. GitHub Actions 下载的 JSON 临时文件
JSON_PATH = os.path.join(os.getcwd(), 'scripts', 'huya_api.json')

# 2. 需要被修改的 Dart 源码文件路径
# 请确保 simple_live_core 文件夹在仓库根目录下
HUYA_FILE_PATH = os.path.join(os.getcwd(), 'simple_live_core', 'lib', 'src', 'huya_site.dart')

def process_api_check():
    print("🚀 启动自动化 API 探测大脑...")

    if not os.path.exists(JSON_PATH):
        print(f"❌ 错误：在 {JSON_PATH} 找不到接口数据")
        return

    try:
        with open(JSON_PATH, 'r', encoding='utf-8') as j:
            data = json.load(j)
        
        # --- 智能节点定位 ---
        # 虎牙搜索结果分散在 "1" (直播中) 和 "3" (全部) 两个节点
        response = data.get('response', {})
        # 优先看节点 1，因为那里的 room_id 最准，如果没有再看节点 3
        docs = response.get('1', {}).get('docs', []) or response.get('3', {}).get('docs', [])
        
        if not docs:
            print("❌ 警告：JSON 数据中没有找到任何文档(docs)，可能接口已大改。")
            return
        
        sample = docs[0]
        print(f"✅ 获取样本成功，正在分析字段特征...")

        # --- 核心字段监控映射表 ---
        # 格式：'代码里的旧Key': ['可能出现的新关键词']
        monitor_fields = {
            'game_subChannel': ['channel', 'subChannel', 'room_id'],
            'game_nick': ['nick', 'name', 'anchor'],
            'game_screenshot': ['screenshot', 'pic', 'img', 'cover'],
            'game_introduction': ['introduction', 'intro', 'roomName', 'title'],
            'game_total_count': ['total_count', 'count', 'online', 'activityCount']
        }

        updates = {}

        # 扫描样本数据，检测代码中的 Key 是否依然存在
        for old_key, keywords in monitor_fields.items():
            if old_key not in sample:
                print(f"⚠️ 发现变动: 字段 '{old_key}' 丢失，尝试匹配候选者...")
                # 在样本的所有 Key 中寻找最匹配的一个
                for new_key in sample.keys():
                    if any(kw in new_key.lower() for kw in keywords):
                        print(f"✨ 找到潜在替代: '{old_key}' -> '{new_key}'")
                        updates[old_key] = new_key
                        break

        # --- 执行代码物理修补 ---
        if updates:
            print(f"🛠️ 正在执行代码修补: {HUYA_FILE_PATH}")
            
            if not os.path.exists(HUYA_FILE_PATH):
                print("❌ 错误：找不到目标 Dart 源码文件，请检查路径。")
                return

            with open(HUYA_FILE_PATH, 'r', encoding='utf-8') as f:
                content = f.read()

            for old_key, new_key in updates.items():
                # 精准替换：只替换引号包裹的字符串定义
                # 示例：item["game_nick"] 会被替换成 item["new_key"]
                old_pattern = f'"{old_key}"'
                new_replacement = f'"{new_key}"'
                if old_pattern in content:
                    content = content.replace(old_pattern, new_replacement)
                    print(f"✅ 已更新代码: {old_pattern} -> {new_replacement}")

            with open(HUYA_FILE_PATH, 'w', encoding='utf-8') as f:
                f.write(content)
            
            print(f"🎉 自动化修复成功！共修改了 {len(updates)} 处字段定义。")
        else:
            print("✅ 完美兼容：当前虎牙接口字段与源码完全匹配，无需修改。")

    except Exception as e:
        print(f"🚨 脚本解析过程中发生崩溃: {str(e)}")

if __name__ == "__main__":
    process_api_check()
