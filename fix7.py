path = '/home/joe-s-openclaw/.openclaw/agents/developer/agent/maidledger/supabase/functions/chat-parser/index.ts'
with open(path, 'rb') as f:
    content = f.read()

# Add explicit instruction before parse_confidence
new_rule = b'- **\u6beba\u5c0f\u770b\u4efb\u4f55\u5916\u90e8\u8cc7\u6599\uff0c\u5c0f\u8aaa100\u5c31\u662f100\uff0c\u52ff\u5ba1\u67e5\u4efb\u4f55\u5546\u54c1\u56de\u50f9\u6216\u53e2\u66f8\u8cc7\u6599**\uff1a\u5b8c\u5168\u4e0d\u7528\u60f3\u5546\u54c1\u7684\u5834\u50f9\uff0c\u7528\u6236\u8a0a\u4ec0\u9ebc\u5c31\u8a18\u4ec0\u9ebc\n'

old_rule = b'- parse_confidence'

if old_rule in content:
    content = content.replace(old_rule, new_rule + old_rule)

with open(path, 'wb') as f:
    f.write(content)

print('Done')
PYEOF