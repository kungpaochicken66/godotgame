#!/usr/bin/env python3
"""A TCP relay that adds latency in both directions (network tests only).

Stands in for a real internet path or TLS proxy in front of the town server, so
timing races that never show on loopback can be reproduced locally.
  python3 scripts/delay_proxy.py LISTEN_PORT TARGET_PORT DELAY_MS [HOLD_MS]
HOLD_MS (optional) holds server-to-client bytes and sends them in one burst after
that long, or together with the close if the server closes first, the way a
buffering proxy or TLS hop can deliver a last message and the close together.
"""
import asyncio
import sys


async def pipe(reader, writer, delay):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            await asyncio.sleep(delay)
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        await asyncio.sleep(delay)   # a close travels as late as the data before it
        try:
            writer.close()
        except Exception:
            pass


async def held_pipe(reader, writer, delay, hold):
    buf = bytearray()
    loop = asyncio.get_running_loop()
    first = None
    try:
        while True:
            timeout = None if first is None else max(0.0, first + hold - loop.time())
            try:
                data = await asyncio.wait_for(reader.read(65536), timeout)
            except asyncio.TimeoutError:
                writer.write(bytes(buf))
                await writer.drain()
                buf.clear()
                first = None
                continue
            if not data:
                break
            if first is None:
                first = loop.time()
            buf += data
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        await asyncio.sleep(delay)
        try:
            writer.write(bytes(buf))   # the held message and the close arrive together
            writer.close()
        except Exception:
            pass


async def main(listen, target, delay, hold=0.0):
    async def handle(cr, cw):
        try:
            sr, sw = await asyncio.open_connection('127.0.0.1', target)
        except OSError:
            cw.close()
            return
        down = held_pipe(sr, cw, delay, hold) if hold > 0 else pipe(sr, cw, delay)
        await asyncio.gather(pipe(cr, sw, delay), down)
    server = await asyncio.start_server(handle, '127.0.0.1', listen)
    async with server:
        await server.serve_forever()


if __name__ == '__main__':
    hold = int(sys.argv[4]) / 1000.0 if len(sys.argv) > 4 else 0.0
    asyncio.run(main(int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]) / 1000.0, hold))
