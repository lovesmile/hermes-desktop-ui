#!/usr/bin/env python3
"""
WeChat iLink Bot — one-shot status check. Returns immediately.
Usage: python3 wechat_qr_check.py <qrcode_value>
Output: {"status":"wait|confirmed|expired"} or {"error":"..."}
"""
import json, sys, os, asyncio

HERMES_HOME = os.environ.get('HERMES_HOME', os.path.expanduser('~/.hermes'))
sys.path.insert(0, os.path.join(HERMES_HOME, 'hermes-agent'))

async def check(qrcode_value):
    from gateway.platforms.weixin import (
        _api_get, ILINK_BASE_URL, EP_GET_QR_STATUS, QR_TIMEOUT_MS, _make_ssl_connector,
    )
    import aiohttp
    async with aiohttp.ClientSession(trust_env=True, connector=_make_ssl_connector()) as session:
        try:
            resp = await _api_get(session, base_url=ILINK_BASE_URL,
                endpoint=f"{EP_GET_QR_STATUS}?qrcode={qrcode_value}",
                timeout_ms=QR_TIMEOUT_MS)
            status = str(resp.get("status") or "wait")
            result = {"status": status}
            if status == "confirmed":
                result.update({
                    "token": str(resp.get("token","")),
                    "account_id": str(resp.get("account_id","")),
                    "nickname": str(resp.get("nickname","")),
                })
            print(json.dumps(result, ensure_ascii=False))
        except Exception as e:
            print(json.dumps({"error": str(e)}, ensure_ascii=False))

if __name__ == '__main__':
    qrcode = sys.argv[1] if len(sys.argv) > 1 else ""
    if not qrcode:
        print(json.dumps({"error": "Missing qrcode_value"}))
    else:
        asyncio.run(check(qrcode))
