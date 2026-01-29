import os
import json
import re

# --- 路径配置 ---
# 1. 刚才 curl 下载的 JSON 临时文件
JSON_PATH = os.path.join(os.getcwd(), 'scripts', 'huya_api.json')

# 2. 需要被修改的 Dart 源码文件路径
# 注意：路径需根据你的实际仓库结构微调，这里假设在 simple_live_core 下
HUYA_FILE_PATH = os.path.join(os.getcwd(), 'simple_live_core', 'lib', 'src', 'huya_site.dart')

def process_api_check():
    print("🔍 正在启动接口分析大脑...")

    # 检查 JSON 文件是否存在
    if not os.path.exists(JSON_PATH):
        print(f"❌ 错误：在 {JSON_PATH} 找不到接口快照文件。")
        return

    try:
        # 读取 JSON 数据
        with open(JSON_PATH, 'r', encoding='utf-8') as j:
            data = json.load(j)
        
        # 按照虎牙目前的结构提取第一条搜索结果作为样本
        # 结构：response -> 3 -> docs -> [0]
        docs = data.get('response', {}).get('3', {}).get('docs', [])
        if not docs:
            print("❌ 警告：JSON 数据中没有找到任何文档(docs)，请检查搜索关键词或接口是否大改。")
            return
        
        sample = docs[0]
        print(f"✅ 成功获取样本 Key 列表: {list(sample.keys())}")

        # --- 核心逻辑：定义字段特征 ---
        # 格式：'代码里的旧Key': ['可能出现的新关键词']
        monitor_fields = {
            'game_subChannel': ['channel', 'room_id', 'id'],
            'game_nick': ['nick', 'name', 'anchor', 'username'],
            'game_screenshot': ['screenshot', 'pic', 'img', 'cover', 'image'],
            'game_introduction': ['introduction', 'roomName', 'title', 'intro'],
            'game_total_count': ['total_count', 'online', 'count', 'viewer']
        }

        updates = {}

        # 扫描样本，看看老 Key 还在不在
        for old_key, keywords in monitor_fields.items():
            if old_key not in sample:
                print(f"⚠️ 发现变动: 字段 '{old_key}' 丢失，正在搜索候选者...")
                # 在样本的所有 Key 中寻找最匹配的一个
                for new_key in sample.keys():
                    if any(kw in new_key.lower() for kw in keywords):
                        print(f"✨ 匹配成功: '{old_key}' -> '{new_key}'")
                        updates[old_key] = new_key
                        break

        # --- 执行代码修补 ---
        if updates:
            print(f"🛠️ 准备修改源码文件: {HUYA_FILE_PATH}")
            
            if not os.path.exists(HUYA_FILE_PATH):
                print("❌ 错误：找不到目标 Dart 文件，请检查路径配置。")
                return

            with open(HUYA_FILE_PATH, 'r', encoding='utf-8') as f:
                content = f.read()

            for old_key, new_key in updates.items():
                # 使用正则或直接替换代码中的字符串定义
                # 寻找类似 "game_nick" 的内容并替换为 "new_key"
                content = content.replace(f'"{old_key}"', f'"{new_key}"')

            with open(HUYA_FILE_PATH, 'w', encoding='utf-8') as f:
                f.write(content)
            
            print(f"🎉 修复完成！共自动修补了 {len(updates)} 处字段定义。")
        else:
            print("✅ 状态良好：当前接口字段与代码配置 100% 吻合，无需修改。")

    except Exception as e:
        print(f"🚨 脚本解析崩溃: {str(e)}")

if __name__ == "__main__":
    process_api_check()
