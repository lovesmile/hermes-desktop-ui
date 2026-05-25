#!/usr/bin/env python3
"""
WeChat iLink Bot — full QR login flow.
1. Fetch QR code → output JSON with qrcode_url
2. Poll for scan status → output NDJSON status lines
3. On confirmed → save credentials to config

Outputs NDJSON: first line is QR data, then status lines, then success/error.
"""
import json
import sys
import os
import asyncio

HERMES_HOME = os.environ.get('HERMES_HOME', os.path.expanduser('~/.hermes'))
AGENT_DIR = os.path.join(HERMES_HOME, 'hermes-agent')
sys.path.insert(0, AGENT_DIR)

async def do_login():
    from gateway.platforms.weixin import qr_login
    try:
        result = await qr_login(hermes_home=HERMES_HOME, bot_type="3", timeout_seconds=300)
        if result:
            print(json.dumps({"done": True, **result}, ensure_ascii=False))
        else:
            print(json.dumps({"error": "Login failed or timed out"}, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"error": f"Login error: {e}"}, ensure_ascii=False))

if __name__ == '__main__':
    asyncio.run(do_login())
