import os
import json

# 文件路径配置
JSON_PATH = os.path.join(os.getcwd(), 'scripts', 'huya_api.json')
HUYA_FILE_PATH = os.path.join(os.getcwd(), 'simple_live_core', 'lib', 'src', 'huya_site.dart')

def main():
    print("🧠 正在启动 API 智能识别系统...")
    if not os.path.exists(JSON_PATH):
        print("❌ 未找到 JSON 数据文件")
        return
    
    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # 智能定位：优先看正在直播节点 "1"
    response = data.get('response', {})
    docs = response.get('1', {}).get('docs', []) or response.get('3', {}).get('docs', [])
    
    if not docs:
        print("❌ 数据节点为空，无法分析")
        return
    
    sample = docs[0]
    
    # 定义核心监控字段和它们的搜索特征
    mapping = {
        'game_subChannel': ['channel', 'subChannel', 'room_id'],
        'game_nick': ['nick', 'name', 'anchor'],
        'game_screenshot': ['screenshot', 'cover', 'pic', 'imgUrl'],
        'game_total_count': ['total_count', 'count', 'online', 'activityCount']
    }

    updates = {}
    for old, keywords in mapping.items():
        if old not in sample:
            print(f"⚠️ 字段 '{old}' 发生变动，寻找替代品...")
            for new in sample.keys():
                if any(kw in new.lower() for kw in keywords):
                    print(f"✨ 匹配成功: '{old}' -> '{new}'")
                    updates[old] = new
                    break
    
    if updates:
        with open(HUYA_FILE_PATH, 'r', encoding='utf-8') as f:
            code = f.read()
        for k, v in updates.items():
            code = code.replace(f'"{k}"', f'"{v}"')
        with open(HUYA_FILE_PATH, 'w', encoding='utf-8') as f:
            f.write(code)
        print(f"🎉 自动化修补成功！已应用以下变动: {updates}")
    else:
        print("✅ 校验通过：代码与接口当前状态完美吻合。")

if __name__ == "__main__":
    main()
