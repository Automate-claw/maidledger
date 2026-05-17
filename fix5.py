path = '/home/joe-s-openclaw/.openclaw/agents/developer/agent/maidledger/supabase/functions/chat-parser/index.ts'
with open(path, 'rb') as f:
    content = f.read()

# Line 264: 金錯値 -> 金錢值
# Actual: e98791e98cafe580a4  (金錯値)
# Target: e98791e98cafe580a4  same? Let me try
content = content.replace(
    '\u91d1\u932f\u503c'.encode('utf-8'),
    '\u91d1\u932f\u5024'.encode('utf-8')
)

# 市價格 -> 市場價格
content = content.replace(
    '\u5e02\u50c9\u683c'.encode('utf-8'),
    '\u5e02\u5834\u50c9\u683c'.encode('utf-8')
)

with open(path, 'wb') as f:
    f.write(content)

print('Done')
with open(path, 'rb') as f:
    lines = f.readlines()
for i in range(260, 267):
    print(lines[i].decode('utf-8', errors='replace'))