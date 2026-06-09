#!/usr/bin/env python3
"""Live UART reader for OpenOtter STM32 bring-up logs.

This script intentionally uses only the Python standard library. It works from
the project .venv without requiring pyserial, which keeps remote debugging and
fresh-machine setup simple on macOS.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import glob
import os
import select
import sys
import termios
import time
from pathlib import Path


DEFAULT_BAUD = 115200
DEFAULT_PORT_PATTERNS = ("/dev/cu.usbmodem*", "/dev/tty.usbmodem*")


def find_ports() -> list[str]:
    ports: list[str] = []
    seen: set[str] = set()
    for pattern in DEFAULT_PORT_PATTERNS:
        for port in sorted(glob.glob(pattern)):
            if port not in seen:
                seen.add(port)
                ports.append(port)
    return ports


def choose_port(requested: str | None) -> str:
    if requested:
        return requested

    env_port = os.environ.get("OPENOTTER_UART")
    if env_port:
        return env_port

    ports = find_ports()
    if not ports:
        raise SystemExit(
            "No /dev/cu.usbmodem* or /dev/tty.usbmodem* ports found. "
            "Connect the IOT01A1 ST-LINK USB port, then retry."
        )

    cu_ports = [p for p in ports if p.startswith("/dev/cu.")]
    selected = cu_ports[0] if cu_ports else ports[0]
    if len(ports) > 1:
        print(
            "Multiple USB modem ports found; using "
            f"{selected}. Pass --port to override.",
            file=sys.stderr,
        )
    return selected


def baud_constant(baud: int) -> int:
    name = f"B{baud}"
    value = getattr(termios, name, None)
    if value is None:
        supported = sorted(
            int(name[1:])
            for name in dir(termios)
            if name.startswith("B") and name[1:].isdigit()
        )
        raise SystemExit(
            f"Baud rate {baud} is not supported by this termios build. "
            f"Supported examples: {supported}"
        )
    return int(value)


def configure_uart(fd: int, baud: int) -> None:
    attrs = termios.tcgetattr(fd)
    attrs[0] &= ~(
        termios.IGNBRK
        | termios.BRKINT
        | termios.PARMRK
        | termios.ISTRIP
        | termios.INLCR
        | termios.IGNCR
        | termios.ICRNL
        | termios.IXON
    )
    attrs[1] &= ~termios.OPOST
    attrs[2] &= ~(termios.CSIZE | termios.PARENB | termios.CSTOPB)
    attrs[2] |= termios.CS8 | termios.CLOCAL | termios.CREAD
    attrs[3] &= ~(
        termios.ECHO
        | termios.ECHONL
        | termios.ICANON
        | termios.ISIG
        | termios.IEXTEN
    )
    speed = baud_constant(baud)
    attrs[4] = speed
    attrs[5] = speed
    termios.tcsetattr(fd, termios.TCSANOW, attrs)


def host_timestamp() -> str:
    return _dt.datetime.now().isoformat(timespec="milliseconds")


class Output:
    def __init__(self, path: Path | None) -> None:
        self._file = path.open("a", encoding="utf-8") if path else None

    def close(self) -> None:
        if self._file:
            self._file.close()

    def write(self, text: str) -> None:
        sys.stdout.write(text)
        sys.stdout.flush()
        if self._file:
            self._file.write(text)
            self._file.flush()


def emit_text(out: Output, text: str, timestamp: bool) -> None:
    if not text:
        return
    if timestamp:
        out.write(f"{host_timestamp()} {text}")
    else:
        out.write(text)


def stream_uart(args: argparse.Namespace) -> int:
    port = choose_port(args.port)
    deadline = time.monotonic() + args.seconds if args.seconds else None
    output = Output(Path(args.output).expanduser() if args.output else None)
    partial = b""

    try:
        while True:
            if deadline is not None and time.monotonic() >= deadline:
                break

            fd: int | None = None
            try:
                fd = os.open(port, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
                configure_uart(fd, args.baud)
            except (OSError, termios.error) as exc:
                if fd is not None:
                    os.close(fd)
                if not args.reconnect:
                    raise SystemExit(f"Failed to open {port}: {exc}") from exc
                print(f"[uart] waiting for {port}: {exc}", file=sys.stderr)
                time.sleep(args.reconnect_delay)
                continue

            print(f"[uart] opened {port} at {args.baud} baud", file=sys.stderr)
            try:
                while True:
                    if deadline is not None and time.monotonic() >= deadline:
                        return 0

                    timeout = 0.25
                    readable, _, _ = select.select([fd], [], [], timeout)
                    if fd not in readable:
                        continue

                    try:
                        chunk = os.read(fd, 4096)
                    except BlockingIOError:
                        continue

                    if not chunk:
                        raise OSError("serial port returned EOF")

                    if args.raw:
                        emit_text(
                            output,
                            chunk.decode("utf-8", errors="replace"),
                            timestamp=False,
                        )
                        continue

                    partial += chunk
                    while b"\n" in partial:
                        line, partial = partial.split(b"\n", 1)
                        text = line.decode("utf-8", errors="replace") + "\n"
                        emit_text(output, text, timestamp=args.timestamp)
            except (OSError, termios.error) as exc:
                if not args.reconnect:
                    raise SystemExit(f"UART read failed: {exc}") from exc
                print(f"[uart] disconnected from {port}: {exc}", file=sys.stderr)
                time.sleep(args.reconnect_delay)
            else:
                break
            finally:
                if fd is not None:
                    os.close(fd)
    except KeyboardInterrupt:
        if partial and not args.raw:
            text = partial.decode("utf-8", errors="replace")
            emit_text(output, text, timestamp=args.timestamp)
        return 130
    finally:
        output.close()

    if partial and not args.raw:
        text = partial.decode("utf-8", errors="replace")
        emit_text(output, text, timestamp=args.timestamp)
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Live-read OpenOtter STM32 UART logs from ST-LINK VCP."
    )
    parser.add_argument(
        "--port",
        help="Serial device path. Defaults to OPENOTTER_UART or first /dev/cu.usbmodem*.",
    )
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    parser.add_argument(
        "--seconds",
        type=float,
        default=0.0,
        help="Stop after this many seconds. Default 0 means run until Ctrl-C.",
    )
    parser.add_argument(
        "--output",
        help="Append captured text to this file while also printing to stdout.",
    )
    parser.add_argument(
        "--timestamp",
        action="store_true",
        help="Prefix decoded lines with host wall-clock timestamps.",
    )
    parser.add_argument(
        "--raw",
        action="store_true",
        help="Print decoded bytes directly instead of line-buffering.",
    )
    parser.add_argument(
        "--no-reconnect",
        dest="reconnect",
        action="store_false",
        help="Exit instead of waiting when the serial device disappears.",
    )
    parser.add_argument(
        "--reconnect-delay",
        type=float,
        default=1.0,
        help="Seconds to wait before reopening a missing/disconnected port.",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List detected ST-LINK serial ports and exit.",
    )
    parser.set_defaults(reconnect=True)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.list:
        ports = find_ports()
        if not ports:
            print("No /dev/cu.usbmodem* or /dev/tty.usbmodem* ports found.")
            return 1
        for port in ports:
            print(port)
        return 0
    return stream_uart(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
