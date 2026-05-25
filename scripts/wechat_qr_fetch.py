#!/usr/bin/env python3
"""
WeChat iLink Bot — phase 1: fetch QR code only (fast, <2s).
Outputs JSON: {"qrcode_url": "...", "qrcode_value": "...", "qr_scan_data": "..."}
"""
import json
import sys
import os
import asyncio

HERMES_HOME = os.environ.get('HERMES_HOME', os.path.expanduser('~/.hermes'))
AGENT_DIR = os.path.join(HERMES_HOME, 'hermes-agent')
sys.path.insert(0, AGENT_DIR)

async def fetch_qr():
    from gateway.platforms.weixin import (
        _api_get, ILINK_BASE_URL, EP_GET_BOT_QR, QR_TIMEOUT_MS, _make_ssl_connector,
    )
    import aiohttp
    async with aiohttp.ClientSession(trust_env=True, connector=_make_ssl_connector()) as session:
        qr_resp = await _api_get(
            session, base_url=ILINK_BASE_URL,
            endpoint=f"{EP_GET_BOT_QR}?bot_type=3", timeout_ms=QR_TIMEOUT_MS,
        )
        qrcode_value = str(qr_resp.get("qrcode") or "")
        qrcode_url = str(qr_resp.get("qrcode_img_content") or "")
        if not qrcode_value:
            return {"error": "QR response missing qrcode"}
        return {
            "qrcode_url": qrcode_url,
            "qrcode_value": qrcode_value,
            "qr_scan_data": qrcode_url if qrcode_url else qrcode_value,
        }

if __name__ == '__main__':
    result = asyncio.run(fetch_qr())
    print(json.dumps(result, ensure_ascii=False))
