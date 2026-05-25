#!/usr/bin/env python3
"""
Test: fetch QR and poll every 3s until expired or confirmed.
Shows how long a QR code stays valid.
"""
import json, sys, os, asyncio, time

HERMES_HOME = os.environ.get('HERMES_HOME', os.path.expanduser('~/.hermes'))
sys.path.insert(0, os.path.join(HERMES_HOME, 'hermes-agent'))
AGENT_DIR = os.path.join(HERMES_HOME, 'hermes-agent')
sys.path.insert(0, AGENT_DIR)

async def test():
    from gateway.platforms.weixin import (
        _api_get, ILINK_BASE_URL, EP_GET_BOT_QR, EP_GET_QR_STATUS,
        QR_TIMEOUT_MS, _make_ssl_connector,
    )
    import aiohttp

    async with aiohttp.ClientSession(trust_env=True, connector=_make_ssl_connector()) as session:
        qr_resp = await _api_get(session, base_url=ILINK_BASE_URL,
            endpoint=f"{EP_GET_BOT_QR}?bot_type=3", timeout_ms=QR_TIMEOUT_MS)
        qrcode_value = str(qr_resp.get("qrcode") or "")
        qrcode_url = str(qr_resp.get("qrcode_img_content") or "")
        print(f"QR fetched at {time.strftime('%H:%M:%S')}")
        print(f"Value: {qrcode_value[:20]}...")
        print(f"URL: {qrcode_url[:60]}...")
        print()

        for i in range(40):  # check for 2 minutes
            await asyncio.sleep(3)
            try:
                resp = await _api_get(session, base_url=ILINK_BASE_URL,
                    endpoint=f"{EP_GET_QR_STATUS}?qrcode={qrcode_value}",
                    timeout_ms=QR_TIMEOUT_MS)
                status = resp.get("status", "unknown")
                now = time.strftime('%H:%M:%S')
                print(f"[{now}] status={status}", flush=True)
                if status in ("confirmed", "expired"):
                    print(f"Done after {i*3+3}s")
                    return
            except asyncio.TimeoutError:
                print(f"[{time.strftime('%H:%M:%S')}] timeout", flush=True)
            except Exception as e:
                print(f"[{time.strftime('%H:%M:%S')}] error: {e}", flush=True)

asyncio.run(test())
