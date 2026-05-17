path = '/home/joe-s-openclaw/.openclaw/agents/developer/agent/maidledger/supabase/functions/chat-parser/index.ts'
with open(path, 'rb') as f:
    content = f.read()

# Fix 金額億先 -> 金額優先 (U+58484 -> U+584AA for the 億/優 byte)
# Full 金額億先: e98791 e9a18d e58484 e58588
# Full 金額優先: e98791 e9a18d e584aa e58588
content = content.replace(b'\xe9\x87\x91\xe9\xa1\x8d\xe5\x84\x84\xe5\x85\x88',  # 金額億先
                       b'\xe9\x87\x91\xe9\xa1\x8d\xe5\x84\xaa\xe5\x85\x88')   # 金額優先

# Fix 換了 -> 提供了
content = content.replace(
    '\u5982\u679c\u7528\u6236\u63db\u4e86\u5546\u54c1\u548c\u91d1\u984d'.encode('utf-8'),
    '\u5982\u679c\u7528\u6236\u63d0\u4f9b\u4e86\u5546\u54c1\u548c\u91d1\u984d'.encode('utf-8')
)

# Fix 金錯值 -> 金錢值
content = content.replace(
    '\u7528\u6236\u8f38\u5165\u7684\u91d1\u932f\u503c'.encode('utf-8'),
    '\u7528\u6236\u8f38\u5165\u7684\u91d1\u932f\u5024'.encode('utf-8')
)

with open(path, 'wb') as f:
    f.write(content)

print('Done')
with open(path, 'rb') as f:
    lines = f.readlines()
for i in range(260, 267):
    print(lines[i].decode('utf-8', errors='replace'))