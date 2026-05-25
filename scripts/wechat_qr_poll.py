#!/usr/bin/env python3
"""
WeChat iLink Bot — phase 2: poll scan status + save credentials.
Takes qrcode_value as argument. Runs until confirmed or timeout.
Outputs NDJSON status lines: {"status":"wait"} / {"status":"confirmed",...} / {"error":"..."}
On confirmed, writes token to config.yaml.
"""
import json
import sys
import os
import asyncio
import time

HERMES_HOME = os.environ.get('HERMES_HOME', os.path.expanduser('~/.hermes'))
AGENT_DIR = os.path.join(HERMES_HOME, 'hermes-agent')
sys.path.insert(0, AGENT_DIR)

def save_credentials(token, account_id, nickname):
    """Save WeChat credentials to config.yaml."""
    import yaml
    config_path = os.path.join(HERMES_HOME, 'config.yaml')
    try:
        with open(config_path) as f:
            config = yaml.safe_load(f) or {}
        if 'platforms' not in config:
            config['platforms'] = {}
        config['platforms']['weixin'] = {
            'token': token,
            'account_id': account_id,
        }
        with open(config_path, 'w') as f:
            yaml.dump(config, f, default_flow_style=False, allow_unicode=True)
        return True
    except Exception as e:
        return False

async def poll(qrcode_value):
    from gateway.platforms.weixin import (
        _api_get, ILINK_BASE_URL, EP_GET_QR_STATUS, QR_TIMEOUT_MS, _make_ssl_connector,
    )
    import aiohttp

    print(json.dumps({"status": "wait"}))
    sys.stdout.flush()

    deadline = time.monotonic() + 300
    async with aiohttp.ClientSession(trust_env=True, connector=_make_ssl_connector()) as session:
        while time.monotonic() < deadline:
            try:
                status_resp = await _api_get(
                    session, base_url=ILINK_BASE_URL,
                    endpoint=f"{EP_GET_QR_STATUS}?qrcode={qrcode_value}",
                    timeout_ms=QR_TIMEOUT_MS,
                )
            except asyncio.TimeoutError:
                await asyncio.sleep(1)
                continue
            except Exception:
                await asyncio.sleep(1)
                continue

            status = str(status_resp.get("status") or "wait")
            print(json.dumps({"status": status}), flush=True)

            if status == "confirmed":
                token = str(status_resp.get("token") or "")
                account_id = str(status_resp.get("account_id") or "")
                nickname = str(status_resp.get("nickname") or "")
                save_credentials(token, account_id, nickname)
                print(json.dumps({
                    "done": True, "token": token,
                    "account_id": account_id, "nickname": nickname,
                }), flush=True)
                return
            elif status == "expired":
                print(json.dumps({"error": "二维码已过期"}), flush=True)
                return

            await asyncio.sleep(2)

    print(json.dumps({"error": "扫描超时"}), flush=True)

if __name__ == '__main__':
    qrcode = sys.argv[1] if len(sys.argv) > 1 else ""
    if not qrcode:
        print(json.dumps({"error": "Missing qrcode_value"}), flush=True)
    else:
        asyncio.run(poll(qrcode))
