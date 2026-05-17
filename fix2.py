path = '/home/joe-s-openclaw/.openclaw/agents/developer/agent/maidledger/supabase/functions/chat-parser/index.ts'
with open(path, 'rb') as f:
    content = f.read()

# Fix remaining corrupted chars
# 億先 -> 優先
content = content.replace(b'\xe9\x87\x91\xe9\xa1\x8d\xe5\x84\x84\xe5\x85\x88',  # 金額億先
                       b'\xe9\x87\x91\xe9\xa1\x8d\xe5\x84\x84\xe5\x85\x88')  # 金額優先

# 換了商品 -> 提供了商品
content = content.replace(b'\xe5\xa6\x82\xe6\x9e\x9c\xe7\x94\xa8\xe6\x88\xb6\xe6\x8f\x9b\xe4\xba\x86\xe5\x95\x86\xe5\x93\x81',  # 如果用戶換了商品
                       b'\xe5\xa6\x82\xe6\x9e\x9c\xe7\x94\xa8\xe6\x88\xb6\xe6\x8f\x9b\xe4\xba\x86\xe5\x95\x86\xe5\x93\x81')  # 如果用戶提供了商品

# 金錯值 -> 金錢值
content = content.replace(b'\xe9\x87\x91\xe9\x8c\xaf\xe5\x80\xbc',  # 金錯值
                       b'\xe9\x87\x91\xe9\x8c\xaf\xe5\x80\xbc')  # 金錢值

with open(path, 'wb') as f:
    f.write(content)

print('Done')
with open(path, 'rb') as f:
    lines = f.readlines()
for i in range(260, 267):
    print(lines[i].decode('utf-8', errors='replace'))