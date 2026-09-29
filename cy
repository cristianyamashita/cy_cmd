#!/usr/bin/env python3
import json
import os
import signal
import subprocess
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
COMMANDS_DIR = BASE_DIR / "commands"
LOGS_DIR = BASE_DIR / "logs"
RUN_DIR = BASE_DIR / "run"


def usage() -> str:
    return """Usage:
  cy
  cy -l | --list
  cy <command> -h | --help
  cy <command> [options]
  cy <background-command> --start
  cy <background-command> --status
  cy <background-command> --stop
  cy <background-command> --restart

Examples:
  cy -l
  cy hello -h
  cy hello -n World
  cy serve --start -p 8080
  cy serve --stop
"""


def load_command_file(path: Path) -> dict:
    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path.name}: invalid JSON: {exc}") from exc

    required = ["name", "description"]
    missing = [key for key in required if not data.get(key)]
    if missing:
        raise ValueError(f"{path.name}: missing required field(s): {', '.join(missing)}")
    if not data.get("cmd_path") and not data.get("cmd"):
        raise ValueError(f"{path.name}: missing required field: cmd_path or cmd")
    if data.get("cmd_path") and data.get("cmd"):
        raise ValueError(f"{path.name}: use only one of cmd_path or cmd")

    data["_config_path"] = str(path)
    data.setdefault("params_map", {})
    data.setdefault("help", "")
    data.setdefault("background", False)
    data.setdefault("aliases", [])
    if not isinstance(data["aliases"], list):
        raise ValueError(f"{path.name}: aliases must be a list")
    return data


def load_commands() -> tuple[dict, dict]:
    commands = {}
    aliases = {}
    errors = []

    if not COMMANDS_DIR.exists():
        return commands, aliases

    for path in sorted(COMMANDS_DIR.glob("*.json")):
        try:
            command = load_command_file(path)
        except ValueError as exc:
            errors.append(str(exc))
            continue

        name = command["name"]
        if name in commands:
            errors.append(f"{path.name}: duplicate command name: {name}")
            continue
        for alias in command.get("aliases", []):
            if alias in commands or alias in aliases:
                errors.append(f"{path.name}: duplicate alias: {alias}")
                continue
            aliases[alias] = name
        commands[name] = command

    if errors:
        print("Configuration warning(s):", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        print(file=sys.stderr)

    return commands, aliases


def list_commands(commands: dict) -> int:
    if not commands:
        print("No commands configured yet.")
        print(f"Add JSON files to: {COMMANDS_DIR}")
        return 0

    width = max(len(name) for name in commands)
    print("Available commands:")
    for name, command in sorted(commands.items()):
        aliases = command.get("aliases", [])
        alias_text = f" (aliases: {', '.join(aliases)})" if aliases else ""
        print(f"  {name.ljust(width)}  {command.get('description', '')}{alias_text}")
    return 0


def command_help(command: dict) -> str:
    help_text = command.get("help", "").strip()
    if help_text:
        return help_text

    lines = [
        f"{command['name']}: {command.get('description', '')}",
        "",
    ]
    if command.get("cmd"):
        lines.append("Inline command")
    else:
        lines.append(f"Command path: {command['cmd_path']}")

    aliases = command.get("aliases", [])
    if aliases:
        lines.extend(["", f"Aliases: {', '.join(aliases)}"])

    params_map = command.get("params_map", {})
    if params_map:
        lines.extend(["", "Parameter aliases:"])
        for alias, target in sorted(params_map.items()):
            lines.append(f"  -{alias} -> --{target}")

    return "\n".join(lines)


def map_arg(arg: str, params_map: dict) -> str:
    if not arg.startswith("-") or arg == "-":
        return arg

    prefix = "--" if arg.startswith("--") else "-"
    raw = arg[2:] if prefix == "--" else arg[1:]
    if "=" in raw:
        alias, value = raw.split("=", 1)
    else:
        alias, value = raw, None

    if alias not in params_map:
        return arg

    target = params_map[alias]
    mapped = target if target.startswith("-") else f"--{target}"
    if value is not None:
        return f"{mapped}={value}"
    return mapped


def resolve_path(raw: str) -> Path:
    """Expand ~ and resolve relative paths against the cy directory."""
    path = Path(os.path.expanduser(raw))
    if not path.is_absolute():
        path = BASE_DIR / path
    return path.resolve()


def command_script(command: dict) -> str | None:
    cmd = command.get("cmd")
    if cmd is None:
        return None
    if isinstance(cmd, list):
        return "\n".join(str(line) for line in cmd)
    return str(cmd)


def build_command(command: dict, args: list[str]) -> list[str]:
    params_map = command.get("params_map", {})
    mapped_args = [map_arg(arg, params_map) for arg in args]
    script = command_script(command)
    if script is not None:
        if mapped_args:
            return ["bash", "-c", script, command["name"], *mapped_args]
        return ["bash", "-c", script]
    cmd_path = resolve_path(command["cmd_path"])
    return [str(cmd_path), *mapped_args]


def command_cwd(command: dict) -> str:
    script = command_script(command)
    if script is not None:
        configured = command.get("cwd")
        if configured:
            return str(resolve_path(configured))
        return str(BASE_DIR)
    cmd_path = resolve_path(command["cmd_path"])
    return str(cmd_path.parent)


def command_slug(command: dict) -> str:
    return command["name"].replace("/", "_")


def pid_path(command: dict) -> Path:
    configured = command.get("pid_path")
    if configured:
        return resolve_path(configured)
    return RUN_DIR / f"{command_slug(command)}.pid"


def log_path(command: dict) -> Path:
    configured = command.get("log_path")
    if configured:
        return resolve_path(configured)
    return LOGS_DIR / f"{command_slug(command)}.log"


def read_pid(path: Path) -> int | None:
    try:
        return int(path.read_text(encoding="utf-8").strip())
    except (FileNotFoundError, ValueError):
        return None


def is_process_running(pid: int | None) -> bool:
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def background_status(command: dict) -> int:
    path = pid_path(command)
    pid = read_pid(path)
    log = log_path(command)

    if is_process_running(pid):
        print(f"{command['name']} is running. PID: {pid}")
        print(f"Log: {log}")
        return 0

    if path.exists():
        path.unlink()
    print(f"{command['name']} is not running.")
    print(f"Log: {log}")
    return 1


def stop_background_command(command: dict) -> int:
    path = pid_path(command)
    pid = read_pid(path)
    if not is_process_running(pid):
        if path.exists():
            path.unlink()
        print(f"{command['name']} is not running.")
        return 0

    os.kill(pid, signal.SIGTERM)
    if path.exists():
        path.unlink()
    print(f"Stopped {command['name']}. PID: {pid}")
    return 0


def start_background_command(command: dict, args: list[str]) -> int:
    script = command_script(command)
    if script is None:
        cmd_path = resolve_path(command["cmd_path"])
        if not cmd_path.exists():
            print(f"Command file not found: {cmd_path}", file=sys.stderr)
            return 127

        if not os.access(cmd_path, os.X_OK):
            print(f"Command file is not executable: {cmd_path}", file=sys.stderr)
            print(f"Run: chmod +x {cmd_path}", file=sys.stderr)
            return 126

    path = pid_path(command)
    pid = read_pid(path)
    if is_process_running(pid):
        print(f"{command['name']} is already running. PID: {pid}")
        print(f"Log: {log_path(command)}")
        return 0

    path.parent.mkdir(parents=True, exist_ok=True)
    log = log_path(command)
    log.parent.mkdir(parents=True, exist_ok=True)
    final_cmd = build_command(command, args)

    try:
        log_file = log.open("ab")
        process = subprocess.Popen(
            final_cmd,
            cwd=command_cwd(command),
            stdin=subprocess.DEVNULL,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    except OSError as exc:
        target = command.get("name", "command")
        print(f"Failed to start {target}: {exc}", file=sys.stderr)
        return 1

    path.write_text(f"{process.pid}\n", encoding="utf-8")
    print(f"Started {command['name']} in background. PID: {process.pid}")
    print(f"Log: {log}")
    return 0


def run_background_command(command: dict, args: list[str]) -> int:
    if args and args[0] == "--start":
        return start_background_command(command, args[1:])
    if args and args[0] == "--status":
        return background_status(command)
    if args and args[0] == "--stop":
        return stop_background_command(command)
    if args and args[0] == "--restart":
        stop_background_command(command)
        return start_background_command(command, args[1:])
    return start_background_command(command, args)


def run_command(command: dict, args: list[str]) -> int:
    if command.get("background"):
        return run_background_command(command, args)

    script = command_script(command)
    if script is None:
        cmd_path = resolve_path(command["cmd_path"])
        if not cmd_path.exists():
            print(f"Command file not found: {cmd_path}", file=sys.stderr)
            return 127

        if not os.access(cmd_path, os.X_OK):
            print(f"Command file is not executable: {cmd_path}", file=sys.stderr)
            print(f"Run: chmod +x {cmd_path}", file=sys.stderr)
            return 126

    final_cmd = build_command(command, args)
    try:
        completed = subprocess.run(final_cmd, cwd=command_cwd(command))
    except OSError as exc:
        target = command.get("name", "command")
        print(f"Failed to execute {target}: {exc}", file=sys.stderr)
        return 1
    return completed.returncode


def main(argv: list[str]) -> int:
    commands, aliases = load_commands()

    if not argv or argv[0] in ("-l", "--list"):
        return list_commands(commands)

    if argv[0] in ("-h", "--help"):
        print(usage())
        return 0

    command_name = aliases.get(argv[0], argv[0])
    command = commands.get(command_name)
    if command is None:
        print(f"Unknown command: {command_name}", file=sys.stderr)
        print(file=sys.stderr)
        list_commands(commands)
        return 2

    command_args = argv[1:]
    if command_args and command_args[0] in ("-h", "--help"):
        print(command_help(command))
        return 0

    return run_command(command, command_args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
