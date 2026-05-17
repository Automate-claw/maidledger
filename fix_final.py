import codecs

path = '/home/joe-s-openclaw/.openclaw/agents/developer/agent/maidledger/supabase/functions/chat-parser/index.ts'

with open(path, 'rb') as f:
    content = f.read()

# Fix corrupted Chinese characters
replacements = [
    ('\u7528\u6236\u660e\u78ba\u8f38\u5165\u7684\u91d1\u984d\u5104\u5148', '\u7528\u6236\u660e\u78ba\u8f38\u5165\u7684\u91d1\u984d\u5121\u5148'),  # 億先 -> 優先
    ('total_amount \u5fc5\u9801\u4f4d\u4ef6', 'total_amount \u5fc5\u9801\u9808\u4f4d'),  # 必頁 -> 必須
    ('\u5982\u679c\u7528\u6236\u63db\u4e86\u5546\u54c1\u548c\u91d1\u984d', '\u5982\u679c\u7528\u6236\u63d0\u4f9b\u4e86\u5546\u54c1\u548c\u91d1\u984d'),  # 換了 -> 提供了
    ('\u91d1\u932f\u503c', '\u91d1\u932f\u5024'),  # 金錯值 -> 金錢值
]

for old, new in replacements:
    content = content.replace(old.encode('utf-8'), new.encode('utf-8'))

with open(path, 'wb') as f:
    f.write(content)

print('Done')

# Verify
with open(path, 'rb') as f:
    lines = f.readlines()
for i in range(260, 267):
    print(repr(lines[i].decode('utf-8', errors='replace')))