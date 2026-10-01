# cursor-plugin-cc

Delega tareas de código desde [Claude Code](https://claude.com/claude-code) a
[Cursor Agent CLI](https://cursor.com/docs/cli/overview) (`cursor-agent`) en
modo headless.

Claude Code sigue siendo el orquestador — escribe la lógica de dominio, define
el contrato de cada subtarea y revisa los diffs. Cursor es **un carril
agéntico extra con su propia cuota**: el delegado lee y edita archivos y
ejecuta comandos en tu repositorio, y `--read-only` lo ejecuta en el modo ask
de Cursor para revisiones y diagnósticos que no deben tocar el árbol de
trabajo. En el **plan Free de Cursor solo corre el modelo `auto`**; los planes
de pago pueden nombrar cualquier modelo que liste `cursor-agent models`.

Hermano de [copilot-plugin-cc](https://github.com/santiquiroz/copilot-plugin-cc),
[antigravity-plugin-cc](https://github.com/santiquiroz/antigravity-plugin-cc),
[ollama-plugin-cc](https://github.com/santiquiroz/ollama-plugin-cc) y
[bipolar-plugin-cc](https://github.com/santiquiroz/bipolar-plugin-cc), todos
inspirados en la estructura de [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc).
**No está afiliado con Cursor (Anysphere), OpenAI, GitHub, Google ni Anthropic.**

> Read this in English: [README.md](README.md)

## Dónde encaja en una cadena de delegación

| Nivel | Delegado | Sirve para |
|---|---|---|
| trivial | [ollama-plugin-cc](https://github.com/santiquiroz/ollama-plugin-cc) | transformaciones de texto de un solo paso en un modelo local pequeño |
| medio (local) | [bipolar-plugin-cc](https://github.com/santiquiroz/bipolar-plugin-cc) | tareas agénticas acotadas en un modelo local grande |
| mecánico | [copilot-plugin-cc](https://github.com/santiquiroz/copilot-plugin-cc) | boilerplate, renombres, specs simples, limpieza |
| **carril agéntico extra** | **cursor-plugin-cc (este)** | tareas acotadas cuando los otros carriles se quedaron sin cuota, segundas opiniones en solo lectura |
| frontier, segundo carril | [antigravity-plugin-cc](https://github.com/santiquiroz/antigravity-plugin-cc) | fallback de Codex, segundas opiniones |
| frontier, primario | Codex / tu delegado principal de razonamiento | implementación cercana a arquitectura, diagnóstico profundo |

Solo existen los carriles que instales; el plugin también funciona solo.

## Requisitos

- Claude Code. El forwarder corre a través de la herramienta Bash (Git Bash en Windows).
- [Cursor Agent CLI](https://cursor.com/docs/cli/installation) — verificado el
  **2026.09.26** y el **2026.09.28** — con sesión iniciada una vez con `cursor-agent login` (o una
  `CURSOR_API_KEY`). Windows PowerShell:
  `irm 'https://cursor.com/install?win32=true' | iex` — macOS/Linux/WSL:
  `curl https://cursor.com/install -fsS | bash`.
- Una cuenta de Cursor. El plan Free funciona, con dos límites: solo `auto`, y
  un cupo mensual de solicitudes de agente.

## Instalación

En Claude Code:

```
/plugin marketplace add santiquiroz/cursor-plugin-cc
/plugin install cursor@cursor-plugin-cc
```

Luego, una vez por máquina:

```
/cursor:setup
```

Setup localiza el CLI, comprueba la versión y el inicio de sesión, crea el
directorio de config propio del plugin `~/.cursor-rescue/` con las reglas de
denegación que usa cada ejecución delegada, opcionalmente verifica que
apliquen (una solicitud de agente), decide si las ejecuciones delegadas deben
aislarse de tus plugins de Claude Code (Windows, ver abajo), y lista los
modelos que tu plan puede usar.

## Uso

```
/cursor:rescue add unit tests for src/utils/money.ts covering rounding and negative amounts (signatures pasted below) ...
/cursor:rescue --background rename UserDto to UserResponse across src/api and update the imports
/cursor:rescue --read-only review src/services/billing.ts for race conditions; report only
```

### Flags y límites

Pon los flags primero, luego el texto de la tarea.

- `--wait` (por defecto) — foreground. Claude Code se bloquea en una llamada a
  `cursor-agent`; una ejecución puede tardar hasta 9 minutos. Interrumpirla no
  revierte nada: lo que Cursor ya editó se queda en tu árbol de trabajo.
- `--background` — el subagente corre en segundo plano y su salida se retransmite
  cuando termina la ejecución. Úsalo para cualquier cosa que dure más de un
  minuto.
- `--model <slug>` — solo planes de pago. En el plan Free el subagente cambia a
  `auto` y lo dice en la primera línea de la salida.
- `--read-only` — ejecuta el modo ask de Cursor (`--mode ask`): se rechazan las
  ediciones de archivos y, en las pruebas, también se rechazaron los comandos
  de shell, así que pega el diff o el código en la tarea en lugar de pedirle a
  Cursor que corra `git diff`.
- `--isolate` / `--no-isolate` — anulan el valor por defecto de aislamiento que
  fijó setup (solo Windows, ver abajo).

Cada ejecución tiene un tope de 9 minutos (`timeout -k 10 540`, por debajo del
techo de la herramienta Bash; `cursor-agent` no tiene print-timeout propio). El
subagente pide `stream-json` e imprime un log de progreso compacto — texto del
asistente, una línea por llamada a herramienta, una línea por denegación — para
que una ejecución cortada por el tope aún muestre qué pasó; las ediciones hechas
hasta entonces están en tu árbol de trabajo. **El modelo `auto` de Cursor en el
plan Free es lento** — en las pruebas una respuesta trivial tardó 20–90 s y una
ejecución con ocho comandos de shell no terminó en 9 minutos — así que acota las
tareas: un archivo de spec, un renombre, una revisión.

**Reanudación.** El subagente agrega `--continue` cuando tu pedido claramente
continúa trabajo previo de Cursor en este repo ("continue", "keep going",
"resume"). Las ejecuciones delegadas mantienen su propia historia de chat (ver
aislamiento abajo en Windows), así que `--continue` retoma la última ejecución
delegada, no tus sesiones interactivas de Cursor.

### Delegación proactiva

La descripción del agente `cursor-rescue` le dice a Claude Code que lo use por
su cuenta cuando tus otros delegados se quedaron sin cuota o están ocupados, o
para una segunda opinión en solo lectura. Esa ejecución envía el texto de la
tarea al backend de Cursor y deja que el modelo edite archivos en el
repositorio actual con llamadas a herramientas autoaprobadas (las reglas de
denegación siguen aplicando). Lo que se interpone entre eso y tu árbol de
trabajo es el sistema de permisos propio de Claude Code: la única herramienta
del subagente es `Bash`, así que en el modo de permisos por defecto apruebas el
comando de lanzamiento antes de que corra, mientras que bajo bypass mode corre
sin preguntar. Si quieres delegación solo bajo pedido, omite el snippet de
CLAUDE.md y agrega esta línea a `~/.claude/CLAUDE.md`:

```
Never launch cursor:cursor-rescue on your own; use it only when I invoke /cursor:rescue explicitly.
```

Para que la delegación proactiva sea rutinaria, pega el bloque de
[docs/claude-md-snippet.md](docs/claude-md-snippet.md) en tu `CLAUDE.md`;
la división de carriles, los topes de WIP y la cadena de fallback están en
[docs/delegation-guide.md](docs/delegation-guide.md).

## Qué ejecuta realmente el forwarder

Simplificado (se muestra el bundle de Windows; en macOS/Linux el launcher es `cursor-agent`):

```bash
export CURSOR_CONFIG_DIR="$HOME/.cursor-rescue"      # plugin-owned cli-config.json with the deny rules
TASK=$(cat <<'EOF_TASK'
<your task, verbatim>

Constraints: work directly in this workspace ... Do not commit, push, switch branches or delete files ...
EOF_TASK
)
MSYS_NO_PATHCONV=1 GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" NO_OPEN_BROWSER=1 \
timeout -k 10 540 "$VER/node.exe" [--require ~/.cursor-rescue/homedir-preload.js] "$VER/index.js" \
  -p "$TASK" --output-format stream-json --trust --workspace "$(pwd -W)" --force --model auto \
  [--mode ask] [--continue] </dev/null 2>&1 | <compact progress filter>
```

## Modelo de seguridad

Hechos sobre `cursor-agent` headless en los que se basa este plugin (verificados el
2026.09.26 y el 2026.09.28, Windows 11):

- `-p` sin `--force` no puede pedir confirmación, así que las llamadas a
  herramientas que necesitan aprobación se rechazan. El forwarder pasa
  `--force`, y las **reglas de denegación `permissions.deny` siguen ganando**
  bajo él (`Command blocked by permissions configuration`).
- `CURSOR_CONFIG_DIR` reubica `cli-config.json`. El plugin mantiene el suyo en
  `~/.cursor-rescue/`, así que sus reglas de denegación aplican solo a las
  ejecuciones delegadas, y tus sesiones interactivas de Cursor conservan tu
  propia configuración. También contiene la **filtración de modelo**:
  `cursor-agent` guarda el último `--model` como modelo por defecto del
  directorio de config con el que corrió — una ejecución de prueba con un
  modelo nombrado dejó la config a nivel de usuario apuntando a un modelo que
  el plan Free no puede usar. El inicio de sesión vive en otro lado
  (`%APPDATA%\Cursor\auth.json` en Windows), así que se comparte.
- Las reglas de denegación coinciden con el **primer comando** de cada llamada
  de shell. En las pruebas, una denegación de `rm` no detuvo `bash -c "rm a.txt"`
  ni `powershell -Command "Remove-Item a.txt"` — el archivo se borró. Por eso las
  reglas del plugin también deniegan los shells envoltorio y runners
  (`bash`, `sh`, `zsh`, `powershell`, `pwsh`, `cmd`, `wsl`, `env`, `xargs`,
  `Start-Process`). Los intérpretes (`node`, `python`, …) no se deniegan — los
  builds y tests los necesitan — así que un delegado determinado aún puede
  borrar a través de un script. Trata la lista como una barandilla, no como un
  sandbox.

La lista de denegación ([docs/cli-config.json](docs/cli-config.json)):

| Reglas | Bloquea |
|---|---|
| `Shell(git push)`, `reset`, `clean`, `checkout`, `switch`, `restore`, `stash`, `rebase`, `commit`, `rm`, `worktree`, `config`, `filter-branch`, `filter-repo`, `update-ref`, `reflog`, `branch -D/-d`, `tag -d`, `gc`, `prune`, and git global options `-C`, `-c`, `--git-dir`, `--work-tree` | estado compartido, descartar trabajo, cambios de historial |
| `Shell(rm)`, `rmdir`, `del`, `erase`, `rd`, `ri`, `Remove-Item`, `unlink`, `shred` | borrar archivos |
| `Shell(bash)`, `sh`, `zsh`, `fish`, `dash`, `powershell`, `pwsh`, `cmd`, `wsl`, `env`, `xargs`, `Start-Process` | shells envoltorio que ocultan los comandos de arriba |
| `Shell(sudo)`, `runas` | escalada de privilegios |
| `Shell(claude)`, `codex`, `copilot`, `agy`, `gemini`, `ollama`, `cursor-agent`, `agent`, `aider`, `opencode`, `amp`, `goose`, `qwen`, `crush` | delegación recursiva a otros AI CLIs |
| `Write(**/.git/**)` | editar metadatos del repositorio |

Lo que esto **no** cubre — conócelo antes de delegar:

- Los comandos de shell corren como tu usuario del SO y pueden alcanzar cualquier
  ruta en disco. El delegado edita tu árbol de trabajo en vivo; no edites los
  mismos archivos mientras una ejecución `--background` está en curso. Haz
  commit o stash de tu propio trabajo primero.
- Web search y fetch son herramientas de Cursor, no comandos de shell; `curl`,
  `npm install` y similares no están denegados. No delegues tareas que procesen
  contenido no confiable.
- `cursor-agent` también fusiona reglas de permisos de `~/.claude/settings.json`
  y `<repo>/.claude/settings.json` en las suyas (las lee al arrancar).
- Los alias de git ya definidos en tu git config corren bajo el nombre del
  alias, así que un alias que hace push no lo atrapa `Shell(git push)`; los
  package runners como `npx` pueden arrancar cualquier herramienta (incluido
  otro AI CLI) detrás de un primer comando permitido. `find … -delete` y el
  borrado vía script tampoco están denegados.

### Aislamiento de tu configuración de Claude Code (Windows)

`cursor-agent` importa tu configuración de Claude Code por su cuenta: los plugins
en `~/.claude/plugins/installed_plugins.json` con sus **hooks**, skills y
agents, `~/.claude/skills`, `~/.claude/agents`, y archivos `CLAUDE.md`. En
Windows ejecuta los comandos de hooks importados a través de PowerShell, así
que un hook escrito para bash falla, y un hook `PreToolUse` que falla
**bloquea la llamada a la herramienta**. Con el plugin claude-mem instalado,
cada escritura y lectura de archivo de una ejecución delegada fue rechazada
(`Hook blocked with message: ... syntax error near unexpected
token`), así que no fue posible ninguna edición.

Las ejecuciones aisladas lo corrigen cargando un preload mínimo en el propio
proceso Node de Cursor que hace que `os.homedir()` devuelva
`~/.cursor-rescue/home`, de modo que Cursor no encuentra `~/.claude` (ni tus
chats y servidores MCP de `~/.cursor`). El entorno de los comandos que ejecuta
el delegado no se toca — `USERPROFILE`, `HOME`, `APPDATA` siguen siendo reales,
así que git, SSH, NuGet, npm y el inicio de sesión siguen funcionando. Setup
activa el aislamiento cuando encuentra plugins de Claude Code con hooks en
Windows; si una ejecución aún choca con `Hook blocked with message`, el
subagente la reejecuta una vez aislada y te lo dice. En macOS/Linux los hooks
corren bajo bash como se espera, y el preload de aislamiento no se usa (la ruta
de inicio de sesión ahí se deriva del directorio home).

## Comportamientos conocidos del CLI de Cursor que este plugin mitiga

| Comportamiento (2026.09.26–28) | Manejo |
|---|---|
| `cursor-agent.cmd` pasa argumentos a través de `cmd.exe`, que corta un prompt multilínea en el primer salto de línea y reinterpreta las comillas | Windows: se llaman directamente el `node.exe` + `index.js` del bundle |
| `--model` se persiste como el modelo por defecto del directorio de config en uso | `CURSOR_CONFIG_DIR` propio del plugin, y `--model` siempre se pasa explícitamente |
| Plan Free: cualquier modelo nombrado falla con `ActionRequiredError: Named models unavailable` | el preflight de `about` lee el tier; Free → `auto` |
| Las reglas de denegación solo coinciden con el primer comando de una llamada de shell | también se deniegan los shells envoltorio y runners |
| Los hooks importados de Claude Code corren a través de PowerShell en Windows y bloquean las llamadas a herramientas cuando fallan | el preload de homedir aísla a Cursor de `~/.claude` |
| Sin print-timeout; la salida de texto se imprime solo al final, así que un timeout lo pierde todo | `timeout -k 10 540` + `stream-json` a través de un filtro de progreso |
| `-p` con un pipe de stdin abierto puede esperar para siempre | stdin se cierra con `</dev/null` |
| Git Bash reescribe argumentos que parecen rutas POSIX, así que una tarea que empieza con `/` llegaría a Cursor alterada | `MSYS_NO_PATHCONV=1`, con rutas estilo Windows construidas por `pwd -W` / `cygpath -w` |
| El modo ask rechaza ediciones y comandos de shell | `--read-only` mapea a modo ask; pega diffs en la tarea |

## Qué hay en el plugin

| Pieza | Propósito |
|---|---|
| `agents/cursor-rescue.md` | Subagente forwarder delgado — una llamada a `cursor-agent -p`, salida compacta |
| `/cursor:rescue` | Delega una tarea de forma explícita (`--background`, `--wait`, `--model`, `--read-only`, `--isolate`) |
| `/cursor:setup` | Localiza el CLI, versión, inicio de sesión, directorio de config del plugin + sonda de denegación, valor por defecto de aislamiento, modelos |
| `docs/cli-config.json` | La config propia del plugin con las reglas de denegación |
| `docs/claude-md-snippet.md` | Bloque de CLAUDE.md listo para pegar |
| `docs/delegation-guide.md` | Guía de orquestación multi-carril |

## Todavía no

- Passthrough de `--worktree` (`cursor-agent -w` crea un git worktree aislado
  bajo `~/.cursor/worktrees/`) — aún no verificado.
- Una variante skill para Codex CLI (copilot-plugin-cc incluye una).
- Indicador de cuota: la API de uso de Cursor existe, pero el CLI no expone un
  comando de uso headless que el forwarder pueda leer antes de una ejecución.

## Licencia

[MIT](LICENSE)
