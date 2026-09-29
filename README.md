# cy_cmd

[Português](README.pt-BR.md)

`cy` is a small command router for macOS (it also works on Linux). Instead of remembering where each of your scripts lives and which flags it takes, you describe each one in a JSON file and run all of them through a single command:

```sh
cy -l                 # list your commands
cy deploy             # run a script that lives in another folder
cy sv --start -p 8080 # start something in background
cy sv --status
cy sv --stop
```

It is a single Python 3 file with no dependencies.

## Features

- One JSON file per command in `commands/`. New files show up in `cy -l` right away.
- Run a script file (`cmd_path`) or inline shell lines (`cmd`).
- Short aliases for command names (`cy sv` instead of `cy serve`).
- Short aliases for parameters (`-p` becomes `--port`) with `params_map`.
- Background commands with `--start`, `--status`, `--stop` and `--restart`, plus PID and log files.
- A help page for each command (`cy <command> -h`).

## Installation

### 1. Download

Clone the repo anywhere you like. This guide uses `~/Projects/cy_cmd`; if you pick another folder, use it in the steps below.

```sh
git clone https://github.com/cristianyamashita/cy_cmd.git ~/Projects/cy_cmd
chmod +x ~/Projects/cy_cmd/cy
```

You can already run it with the full path:

```sh
~/Projects/cy_cmd/cy -l
```

### 2. Add the folder to your `PATH`

To type only `cy` from any folder, add the `cy_cmd` folder to the `PATH` variable. The shell looks for commands in the folders listed in `PATH`.

Put this line at the end of your shell config file. Change the path if you cloned the repo somewhere else:

```sh
export PATH="$HOME/Projects/cy_cmd:$PATH"
```

Which file to edit depends on your shell. Run `echo $SHELL` to see which shell you use.

| System | Shell | File |
| --- | --- | --- |
| macOS (default since Catalina) | zsh | `~/.zshrc` |
| macOS | bash | `~/.bash_profile` |
| Linux (most distributions) | bash | `~/.bashrc` |
| Linux | zsh | `~/.zshrc` |

You can also append the line from the terminal. For zsh:

```sh
echo 'export PATH="$HOME/Projects/cy_cmd:$PATH"' >> ~/.zshrc
```

For bash on Linux:

```sh
echo 'export PATH="$HOME/Projects/cy_cmd:$PATH"' >> ~/.bashrc
```

Use single quotes as shown, so `$HOME` and `$PATH` are saved as written and expanded each time a shell starts.

### 3. Reload and test

Open a new terminal, or reload the file you edited (for example `source ~/.zshrc` or `source ~/.bashrc`). Then check:

```sh
command -v cy        # should print .../cy_cmd/cy
cy -l
cy hello -n World
```

If you get `command not found`, check that the path in the `export` line is the folder that contains `cy`, and that `cy` is executable (`chmod +x`).

### Uninstall

Remove the `export PATH=...` line from your shell config file and delete the `cy_cmd` folder.

## Bundled commands

| Command | Alias | What it shows |
| --- | --- | --- |
| `hello` | `hi` | Inline command with a parameter alias (`-n` → `--name`). |
| `sysinfo` | `si` | Inline command with several lines. |
| `ping_hosts` | `ph` | Script file (`cmd_path`) with `params_map`. |
| `serve` | `sv` | Background command: a local web server for `examples/site`. |

More templates, which you must edit before using them, are in [`examples/commands/`](examples/commands): SSH deploy, AWS SSM session, GitHub CLI account switch, a build script with `cwd`, and a background server with custom log and PID paths. Copy one into `commands/` and edit it.

## Command JSON

Create one file per command in `commands/`, for example `commands/deploy.json`:

```json
{
  "name": "deploy",
  "aliases": ["dp"],
  "description": "Deploy my app.",
  "cmd_path": "~/Projects/my-app/scripts/deploy.sh",
  "params_map": {
    "e": "env",
    "v": "verbose"
  },
  "help": "Deploy my app.\n\nExamples:\ncy deploy -e staging\ncy dp -e prod -v"
}
```

### Fields

| Field | Required | Description |
| --- | --- | --- |
| `name` | yes | Command name. Must be unique. |
| `description` | yes | One line, shown in `cy -l`. |
| `cmd_path` | one of `cmd_path` / `cmd` | Script to run. It must be executable (`chmod +x`). It runs with its own folder as the working directory. |
| `cmd` | one of `cmd_path` / `cmd` | Inline shell script, as a string or a list of lines. It runs with `bash -c`, and the arguments are available as `"$@"`. |
| `cwd` | no | Working directory for `cmd`. Default: the `cy` folder. |
| `aliases` | no | List of short names. |
| `params_map` | no | Parameter aliases (see below). |
| `help` | no | Text shown by `cy <command> -h`. If it is missing, `cy` builds a help page for you. |
| `background` | no | `true` runs the command in background (see below). |
| `log_path` | no | Log file for background commands. Default: `logs/<name>.log`. |
| `pid_path` | no | PID file for background commands. Default: `run/<name>.pid`. |

Paths accept `~`. Relative paths are resolved from the `cy` folder, so a command can point to a script that ships in this repo.

### `params_map`

The key is the alias you type after `cy`. The value is the parameter passed to the real script.

If the value does not start with `-`, `cy` turns it into a long flag:

```json
{ "e": "env" }
```

```sh
cy deploy -e staging
# runs: deploy.sh --env staging
```

If the real script uses a specific flag, write the full flag:

```json
{ "e": "-E", "v": "--verbose-mode" }
```

```sh
cy deploy -e staging -v
# runs: deploy.sh -E staging --verbose-mode
```

`-e=staging` also works and becomes `--env=staging`. Parameters that are not in the map are passed through unchanged.

### Background commands

With `"background": true`:

```sh
cy serve              # same as --start
cy serve --start -p 8080
cy serve --status
cy serve --stop
cy serve --restart
```

Output goes to the log file, and the PID is saved so `--status` and `--stop` can find the process.

## License

[MIT](LICENSE)
