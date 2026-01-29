import os
import json

JSON_PATH = os.path.join(os.getcwd(), 'scripts', 'huya_api.json')
HUYA_FILE_PATH = os.path.join(os.getcwd(), 'simple_live_core', 'lib', 'src', 'huya_site.dart')

def main():
    if not os.path.exists(JSON_PATH): return
    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    response = data.get('response', {})
    # 强制监控节点 "3"，因为它才是封面的来源
    docs = response.get('3', {}).get('docs', [])
    if not docs: return
    sample = docs[0]
    
    mapping = {
        'game_subChannel': ['channel', 'room_id'],
        'game_nick': ['nick', 'name', 'anchor'],
        'game_screenshot': ['screenshot', 'cover', 'pic', 'imgUrl'],
        'game_total_count': ['total_count', 'online', 'activityCount']
    }

    updates = {}
    for old, keywords in mapping.items():
        if old not in sample:
            for new in sample.keys():
                if any(kw in new.lower() for kw in keywords):
                    updates[old] = new
                    break
    
    if updates:
        with open(HUYA_FILE_PATH, 'r', encoding='utf-8') as f:
            code = f.read()
        for k, v in updates.items():
            code = code.replace(f'"{k}"', f'"{v}"')
        with open(HUYA_FILE_PATH, 'w', encoding='utf-8') as f:
            f.write(code)
        print(f"自动化修复成功: {updates}")

if __name__ == "__main__":
    main()
