import os
import json

# 定义文件路径
JSON_PATH = os.path.join(os.getcwd(), 'scripts', 'huya_api.json')
HUYA_FILE_PATH = os.path.join(os.getcwd(), 'simple_live_core', 'lib', 'src', 'huya_site.dart')

def main():
    if not os.path.exists(JSON_PATH): return
    
    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # 提取虎牙搜索结果的第一条文档
    docs = data.get('response', {}).get('3', {}).get('docs', [])
    if not docs: return
    sample = docs[0]

    # 我们关心的字段特征表
    mapping = {
        'game_subChannel': ['channel', 'room_id', 'id'],
        'game_nick': ['nick', 'name', 'anchor'],
        'game_screenshot': ['screenshot', 'cover', 'pic']
    }

    updates = {}
    for old_key, keywords in mapping.items():
        if old_key not in sample:
            # 尝试在返回的 JSON 里找长得像的 Key
            for new_key in sample.keys():
                if any(k in new_key.lower() for k in keywords):
                    updates[old_key] = new_key
                    break
    
    if updates:
        print(f"检测到字段变动: {updates}")
        with open(HUYA_FILE_PATH, 'r', encoding='utf-8') as f:
            code = f.read()
        
        for old, new in updates.items():
            code = code.replace(f'"{old}"', f'"{new}"')
            
        with open(HUYA_FILE_PATH, 'w', encoding='utf-8') as f:
            f.write(code)
    else:
        print("一切正常，接口字段未变。")

if __name__ == "__main__":
    main()
