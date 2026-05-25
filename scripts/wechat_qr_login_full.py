#!/usr/bin/env python3
"""
WeChat iLink Bot QR login — full lifecycle.
Fetches QR code, polls status until confirmed/expired/timeout.
Outputs one JSON line per event for Flutter to consume as stream.
"""
import json, asyncio, aiohttp, sys, ssl

ILINK_BASE_URL = "https://ilinkai.weixin.qq.com"
EP_GET_BOT_QR = "/ilink/bot/get_bot_qrcode"
EP_QR_STATUS = "/ilink/bot/get_qrcode_status"
POLL_INTERVAL = 1.5  # seconds between polls
MAX_POLL_SEC = 480   # 8 minutes
MAX_RETRIES = 3


def _out(data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


async def main():
    ssl_ctx = ssl.create_default_context()
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE
    connector = aiohttp.TCPConnector(ssl=ssl_ctx)
    timeout = aiohttp.ClientTimeout(total=35)

    async with aiohttp.ClientSession(
        trust_env=True, connector=connector, timeout=timeout
    ) as session:
        for attempt in range(1, MAX_RETRIES + 1):
            # ─── Step 1: Fetch QR code ───────────────────────────
            # NOTE: iLink API returns JSON with Content-Type: application/octet-stream,
            #       so aiohttp's resp.json() refuses to parse. We read raw text instead.
            try:
                async with session.get(
                    f"{ILINK_BASE_URL}{EP_GET_BOT_QR}?bot_type=3"
                ) as resp:
                    body = json.loads(await resp.text())
            except Exception as e:
                _out({"status": "error", "error": f"请求二维码失败: {e}"})
                return

            qrcode_value = str(body.get("qrcode") or "")
            qrcode_url = str(body.get("qrcode_img_content") or "")
            if not qrcode_value:
                _out({"status": "error", "error": "API 返回缺少 qrcode 字段"})
                return

            _out({
                "status": "qr_ready",
                "qrcode_value": qrcode_value,
                "qrcode_url": qrcode_url or qrcode_value,
                "attempt": attempt,
                "max_attempts": MAX_RETRIES,
            })

            # ─── Step 2: Poll status ─────────────────────────────
            loop = asyncio.get_event_loop()
            deadline = loop.time() + MAX_POLL_SEC
            start_time = loop.time()

            while loop.time() < deadline:
                await asyncio.sleep(POLL_INTERVAL)
                try:
                    async with session.get(
                        f"{ILINK_BASE_URL}{EP_QR_STATUS}?qrcode={qrcode_value}"
                    ) as resp:
                        body = json.loads(await resp.text())
                except Exception:
                    continue

                elapsed = int(loop.time() - start_time)
                remaining = max(0, MAX_POLL_SEC - elapsed)
                status = body.get("status", "")

                if status == "confirmed":
                    _out({
                        "status": "confirmed",
                        "ilink_bot_id": body.get("ilink_bot_id", ""),
                        "bot_token": body.get("bot_token", ""),
                        "baseurl": body.get("baseurl", ILINK_BASE_URL),
                    })
                    return

                elif status == "expired":
                    _out({"status": "expired", "attempt": attempt})
                    break  # try next retry

                elif status == "0":
                    _out({"status": "waiting_scan", "remaining": remaining})

                elif status == "scaned_but_redirect":
                    _out({
                        "status": "scanned",
                        "redirect_host": body.get("redirect_host", ""),
                    })

                else:
                    _out({"status": "unknown", "status_code": status, "remaining": remaining})

            else:
                # loop finished without break → timeout
                _out({"status": "timeout"})
                return

        # All retries exhausted
        _out({"status": "failed", "error": "二维码已过期，重试次数已达上限"})


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except Exception as e:
        _out({"status": "error", "error": str(e)})
