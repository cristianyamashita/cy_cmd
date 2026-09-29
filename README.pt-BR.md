# cy_cmd

[English](README.md)

`cy` é um pequeno roteador de comandos para macOS (também funciona no Linux). Em vez de lembrar onde fica cada script e quais parâmetros ele usa, você descreve cada um em um arquivo JSON e executa todos por um único comando:

```sh
cy -l                 # lista os comandos
cy deploy             # executa um script que está em outra pasta
cy sv --start -p 8080 # inicia algo em background
cy sv --status
cy sv --stop
```

É um único arquivo Python 3, sem dependências.

## Recursos

- Um arquivo JSON por comando em `commands/`. Arquivos novos aparecem em `cy -l` na hora.
- Executa um arquivo de script (`cmd_path`) ou linhas de shell inline (`cmd`).
- Apelidos curtos para os comandos (`cy sv` em vez de `cy serve`).
- Apelidos curtos para os parâmetros (`-p` vira `--port`) com `params_map`.
- Comandos em background com `--start`, `--status`, `--stop` e `--restart`, com arquivos de PID e de log.
- Uma página de ajuda para cada comando (`cy <comando> -h`).

## Instalação

### 1. Baixar

Clone o repositório em qualquer pasta. Este guia usa `~/Projects/cy_cmd`; se escolher outra pasta, use-a nos passos abaixo.

```sh
git clone https://github.com/cristianyamashita/cy_cmd.git ~/Projects/cy_cmd
chmod +x ~/Projects/cy_cmd/cy
```

Já dá para executar usando o caminho completo:

```sh
~/Projects/cy_cmd/cy -l
```

### 2. Adicionar a pasta ao `PATH`

Para digitar só `cy` em qualquer pasta, adicione a pasta `cy_cmd` à variável `PATH`. O shell procura os comandos nas pastas listadas no `PATH`.

Coloque esta linha no final do arquivo de configuração do seu shell. Troque o caminho se você clonou o repositório em outro lugar:

```sh
export PATH="$HOME/Projects/cy_cmd:$PATH"
```

O arquivo a editar depende do seu shell. Rode `echo $SHELL` para ver qual você usa.

| Sistema | Shell | Arquivo |
| --- | --- | --- |
| macOS (padrão desde o Catalina) | zsh | `~/.zshrc` |
| macOS | bash | `~/.bash_profile` |
| Linux (maioria das distribuições) | bash | `~/.bashrc` |
| Linux | zsh | `~/.zshrc` |

Também dá para adicionar a linha pelo terminal. Para zsh:

```sh
echo 'export PATH="$HOME/Projects/cy_cmd:$PATH"' >> ~/.zshrc
```

Para bash no Linux:

```sh
echo 'export PATH="$HOME/Projects/cy_cmd:$PATH"' >> ~/.bashrc
```

Use aspas simples como no exemplo, para que `$HOME` e `$PATH` sejam gravados como estão e expandidos cada vez que um shell abre.

### 3. Recarregar e testar

Abra um terminal novo, ou recarregue o arquivo que você editou (por exemplo `source ~/.zshrc` ou `source ~/.bashrc`). Depois confira:

```sh
command -v cy        # deve mostrar .../cy_cmd/cy
cy -l
cy hello -n Mundo
```

Se aparecer `command not found`, confira se o caminho na linha `export` é a pasta que contém o `cy` e se o `cy` é executável (`chmod +x`).

### Desinstalar

Remova a linha `export PATH=...` do arquivo de configuração do shell e apague a pasta `cy_cmd`.

## Comandos incluídos

| Comando | Apelido | O que demonstra |
| --- | --- | --- |
| `hello` | `hi` | Comando inline com apelido de parâmetro (`-n` → `--name`). |
| `sysinfo` | `si` | Comando inline com várias linhas. |
| `ping_hosts` | `ph` | Arquivo de script (`cmd_path`) com `params_map`. |
| `serve` | `sv` | Comando em background: um servidor web local para `examples/site`. |

Outros modelos, que precisam ser editados antes do uso, estão em [`examples/commands/`](examples/commands): deploy via SSH, sessão AWS SSM, troca de conta do GitHub CLI, script de build com `cwd` e servidor em background com caminhos próprios de log e PID. Copie um deles para `commands/` e edite.

## JSON de comando

Crie um arquivo por comando em `commands/`, por exemplo `commands/deploy.json`:

```json
{
  "name": "deploy",
  "aliases": ["dp"],
  "description": "Faz o deploy do meu app.",
  "cmd_path": "~/Projects/my-app/scripts/deploy.sh",
  "params_map": {
    "e": "env",
    "v": "verbose"
  },
  "help": "Faz o deploy do meu app.\n\nExemplos:\ncy deploy -e staging\ncy dp -e prod -v"
}
```

### Campos

| Campo | Obrigatório | Descrição |
| --- | --- | --- |
| `name` | sim | Nome do comando. Deve ser único. |
| `description` | sim | Uma linha, mostrada em `cy -l`. |
| `cmd_path` | um entre `cmd_path` / `cmd` | Script a executar. Precisa ser executável (`chmod +x`). Roda usando a própria pasta como diretório de trabalho. |
| `cmd` | um entre `cmd_path` / `cmd` | Script de shell inline, como texto ou lista de linhas. Roda com `bash -c`, e os argumentos ficam em `"$@"`. |
| `cwd` | não | Diretório de trabalho para `cmd`. Padrão: a pasta do `cy`. |
| `aliases` | não | Lista de nomes curtos. |
| `params_map` | não | Apelidos de parâmetros (veja abaixo). |
| `help` | não | Texto mostrado por `cy <comando> -h`. Se não existir, o `cy` monta uma ajuda automática. |
| `background` | não | `true` executa o comando em background (veja abaixo). |
| `log_path` | não | Arquivo de log dos comandos em background. Padrão: `logs/<name>.log`. |
| `pid_path` | não | Arquivo de PID dos comandos em background. Padrão: `run/<name>.pid`. |

Os caminhos aceitam `~`. Caminhos relativos partem da pasta do `cy`, então um comando pode apontar para um script que vem neste repositório.

### `params_map`

A chave é o apelido que você digita depois do `cy`. O valor é o parâmetro enviado para o script real.

Se o valor não começa com `-`, o `cy` transforma em parâmetro longo:

```json
{ "e": "env" }
```

```sh
cy deploy -e staging
# executa: deploy.sh --env staging
```

Se o script real usa uma flag específica, escreva a flag completa:

```json
{ "e": "-E", "v": "--verbose-mode" }
```

```sh
cy deploy -e staging -v
# executa: deploy.sh -E staging --verbose-mode
```

`-e=staging` também funciona e vira `--env=staging`. Parâmetros que não estão no mapa são repassados sem mudança.

### Comandos em background

Com `"background": true`:

```sh
cy serve              # o mesmo que --start
cy serve --start -p 8080
cy serve --status
cy serve --stop
cy serve --restart
```

A saída vai para o arquivo de log, e o PID fica salvo para que `--status` e `--stop` encontrem o processo.

## Licença

[MIT](LICENSE)
