# cursor-plugin-cc

Delega tareas de código desde [Claude Code](https://claude.com/claude-code) a
[Cursor Agent CLI](https://cursor.com/docs/cli/overview) (`cursor-agent`) en
modo headless.

Claude Code sigue siendo el orquestador — escribe la lógica de dominio, define
el contrato de cada subtarea y revisa los diffs. El delegado es agéntico: lee y
edita archivos y ejecuta comandos en tu repositorio, bajo un directorio de
config propio del plugin cuyas reglas de denegación bloquean las operaciones
peligrosas (ver Modelo de seguridad). `--read-only` lo ejecuta en el modo ask
de Cursor para revisiones y diagnósticos que no deben tocar el árbol de
trabajo. En el **plan Free de Cursor solo corre el modelo `auto`** y los turnos
son lentos; los planes de pago pueden nombrar cualquier modelo que liste
`cursor-agent models`.

> Read this in English: [README.md](README.md)

## Cuándo conviene

- **Cuota propia.** Cada ejecución delegada gasta solicitudes de agente del
  cupo mensual de tu plan de Cursor, no tu uso de Claude Code — útil cuando
  quieres repartir trabajo entre ambos.
- **Tareas acotadas y bien especificadas.** Un archivo de spec, un renombre,
  boilerplate, un build fix — trabajo que el delegado puede terminar sin
  preguntar por qué.
- **Segundas opiniones en solo lectura.** `--read-only` ejecuta el modo ask de
  Cursor, que rechaza ediciones de archivos (y en las pruebas también rechazó
  los comandos de shell), así que las revisiones y diagnósticos no tocan tu
  árbol de trabajo. Pega el diff o el código en la tarea.
- **Límites honestos del plan Free.** Solo corre `auto` — cualquier modelo
  nombrado falla — y los turnos son lentos: en las pruebas una respuesta
  trivial tardó 20–90 s y una ejecución con ocho comandos de shell no terminó
  en 9 minutos. Acota las tareas.

No sirve para: lógica de dominio, reglas de negocio, decisiones de
arquitectura — todo lo donde el PORQUÉ vive en tu conversación se queda en el
hilo principal.

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

## Setup

Luego, una vez por máquina:

```
/cursor:setup
```

Setup localiza el CLI, comprueba la versión (piso **2026.09.26** — si es más
viejo sugiere `cursor-agent update`) y el inicio de sesión, crea el directorio
de config propio del plugin `~/.cursor-rescue/` con las reglas de denegación
que usa cada ejecución delegada, opcionalmente verifica que apliquen (una
solicitud de agente), decide si las ejecuciones delegadas deben aislarse de tus
plugins de Claude Code (Windows, ver abajo), y lista los modelos que tu plan
puede usar.

Por qué su propio directorio: cada ejecución delegada fija `CURSOR_CONFIG_DIR`
en `~/.cursor-rescue/`, así que las reglas de denegación aplican solo a las
ejecuciones delegadas y tus sesiones interactivas de Cursor conservan tu propia
configuración. También contiene una peculiaridad de `cursor-agent` — el CLI
guarda el último `--model` como modelo por defecto del directorio de config
con el que corrió, y un modelo nombrado dejado en la config a nivel de usuario
rompe cada ejecución posterior en el plan Free.

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
plan Free es lento**, así que acota las tareas: un archivo de spec, un renombre,
una revisión.

### Reanudación

El subagente agrega `--continue` cuando tu pedido claramente continúa trabajo
previo de Cursor en este repo ("continue", "keep going", "resume"). Las
ejecuciones delegadas mantienen su propia historia de chat (ver aislamiento
abajo en Windows), así que `--continue` retoma la última ejecución delegada, no
tus sesiones interactivas de Cursor.

### Delegación proactiva

La descripción del agente `cursor-rescue` deja que Claude Code lo use por su
cuenta para tareas acotadas y segundas opiniones en solo lectura. Esa ejecución
envía el texto de la tarea al backend de Cursor y deja que el modelo edite
archivos en el repositorio actual con llamadas a herramientas autoaprobadas
(las reglas de denegación siguen aplicando). Lo que se interpone entre eso y tu
árbol de trabajo es el sistema de permisos propio de Claude Code: la única
herramienta del subagente es `Bash`, así que en el modo de permisos por defecto
apruebas el comando de lanzamiento antes de que corra, mientras que bajo bypass
mode corre sin preguntar. Que la delegación ocurra de forma proactiva o solo
bajo pedido es tu decisión — defínela en tu `CLAUDE.md`. Si quieres delegación
solo bajo pedido, agrega esta línea a `~/.claude/CLAUDE.md`:

```
Never launch cursor:cursor-rescue on your own; use it only when I invoke /cursor:rescue explicitly.
```

[docs/claude-md-snippet.md](docs/claude-md-snippet.md) es un bloque inicial
listo para pegar; adapta sus disparadores a tu configuración.

### Qué se ejecuta por debajo

El subagente hace dos llamadas Bash a `scripts/cursor-forward.sh`, que concentra
cada paso determinista (probado con un `cursor-agent` falso en `tests/run.sh`):

```bash
bash scripts/cursor-forward.sh preflight [--model <slug>] [--isolate|--no-isolate]
bash scripts/cursor-forward.sh run --model <slug> [--read-only] [--continue] <<'CURSOR_TASK_<nonce>'
<your task, verbatim>
CURSOR_TASK_<nonce>
```

`preflight` encuentra el launcher, comprueba las reglas de denegación, lee
versión, plan e inicio de sesión con `cursor-agent about` (sin turno de agente)
y elige el modelo (`auto` en el plan Free). `run` luego ejecuta, simplificado
para el bundle de Windows (en macOS/Linux el launcher es `cursor-agent`):

```bash
CURSOR_CONFIG_DIR=~/.cursor-rescue MSYS2_ARG_CONV_EXCL='*' GIT_TERMINAL_PROMPT=0 \
GIT_SSH_COMMAND="ssh -o BatchMode=yes" NO_OPEN_BROWSER=1 \
timeout -k 10 540 "$VER/node.exe" --require scripts/cursor-preload.js "$VER/index.js" \
  -p "<task + constraints>" --output-format stream-json --trust --workspace "<repo>" \
  --force --model auto [--mode ask] [--continue] </dev/null 2>&1 | node scripts/stream-filter.js
```

y agrega una línea `[cursor-rescue] WARNING: <what changed> — review before your
next git command` cuando la ejecución movió `HEAD`, cambió de rama, alteró la
lista de stash, el git config o los hooks (informa, nunca revierte).

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

**Revisa el diff.** La salida del delegado es de confianza media: un modelo
agéntico hizo el trabajo con llamadas a herramientas autoaprobadas. Revisa
`git status`, `git diff`, `git log` y `git stash list` antes de hacer commit; el
orquestador es dueño del commit.

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

## Configuración

El plugin es dueño de `~/.cursor-rescue/` (cambia la ubicación con
`CURSOR_RESCUE_HOME`):

| Archivo | Propósito |
|---|---|
| `cli-config.json` | Reglas de denegación para las ejecuciones delegadas (plantilla: `docs/cli-config.json`). El subagente se niega a correr sin las reglas críticas (exit 78). |
| `isolate` | `on` u `off` — valor por defecto de aislamiento que escribe setup (Windows). Se anula por ejecución con `--isolate` / `--no-isolate`. |

Variables de entorno que el forwarder entiende (todas opcionales):

| Variable | Propósito |
|---|---|
| `CURSOR_API_KEY` / `CURSOR_AUTH_TOKEN` | Inicio de sesión sin `cursor-agent login`. |
| `CURSOR_RESCUE_HOME` | Mueve el directorio de config del plugin a otro lado. |
| `CURSOR_RESCUE_TIMEOUT` | Tope de ejecución en segundos (por defecto 540). |
| `CURSOR_AGENT_BIN` | Usa este binario `cursor-agent` en lugar de buscarlo. |
| `CURSOR_AGENT_NODE` + `CURSOR_AGENT_INDEX` | Usa este bundle de Windows directamente (`node.exe` + `index.js`). |

Selección de modelo: pasa `--model <slug>` con cualquier slug que liste
`cursor-agent models` (setup los muestra); en el plan Free el preflight cambia
a `auto` y lo dice. `--model` siempre se pasa explícitamente, y gracias a
`CURSOR_CONFIG_DIR` solo se recuerda dentro de `~/.cursor-rescue/`.

Diseño del repositorio:

| Pieza | Propósito |
|---|---|
| `agents/cursor-rescue.md` | Subagente forwarder delgado — llamadas `preflight` y `run`, salida devuelta tal cual |
| `scripts/cursor-forward.sh` | Descubrimiento del launcher, puerta de denegación, preflight de plan/modelo, aislamiento, timeout, avisos de cambio de git |
| `scripts/stream-filter.js` | `stream-json` → log de progreso compacto |
| `scripts/cursor-preload.js` | Solo bundle de Windows (`node --require`): limpia la variable MSYS dentro de Cursor y, al aislar, apunta `os.homedir()` lejos de `~/.claude` |
| `tests/run.sh` | Tests herméticos con un `cursor-agent` falso — `bash tests/run.sh` |
| `/cursor:rescue` | Delega una tarea de forma explícita (`--background`, `--wait`, `--model`, `--read-only`, `--isolate`) |
| `/cursor:setup` | Localiza el CLI, versión, inicio de sesión, directorio de config del plugin + sonda de denegación, valor por defecto de aislamiento, modelos |
| `docs/cli-config.json` | La config propia del plugin con las reglas de denegación |
| `docs/claude-md-snippet.md` | Bloque inicial de CLAUDE.md listo para pegar |
| `docs/delegation-guide.md` | Guía de delegación (sirve con Cursor solo o junto a otros delegados) |

## Solución de problemas

Cada fila de abajo es un comportamiento verificado el 2026.09.26–28
(Windows 11) más el manejo que aplica el plugin.

| Síntoma | Causa | Manejo |
|---|---|---|
| Un prompt multilínea llega cortado en el primer salto de línea | `cursor-agent.cmd` pasa argumentos a través de `cmd.exe`, que reinterpreta las comillas | En Windows se llaman directamente el `node.exe` + `index.js` del bundle |
| Las sesiones interactivas se rompen tras una ejecución con modelo nombrado | `--model` se persiste como el modelo por defecto del directorio de config en uso | `CURSOR_CONFIG_DIR` propio del plugin, y `--model` siempre se pasa explícitamente |
| `ActionRequiredError: Named models unavailable` | Plan Free con un modelo nombrado | El preflight de `about` lee el tier; Free → `auto`. Si igual se cuela, el subagente reejecuta una vez en `auto` |
| `rm` denegado pero `bash -c "rm …"` igual borra | Las reglas de denegación solo coinciden con el primer comando de una llamada de shell | También se deniegan los shells envoltorio y runners — sigue siendo una barandilla, no un sandbox |
| `Hook blocked with message` en cada lectura y escritura de archivo | Los hooks importados de Claude Code corren a través de PowerShell en Windows y bloquean las llamadas a herramientas cuando fallan | El preload de homedir aísla a Cursor de `~/.claude`; el subagente reejecuta una vez aislado (corre `/cursor:setup` para que sea el valor por defecto) |
| Ejecución cortada a los 9 minutos con salida parcial | Sin print-timeout; la salida de texto se imprime solo al final | `timeout -k 10 540` + `stream-json` a través de un filtro de progreso, así el progreso parcial sobrevive |
| Ejecución colgada sin salida | `-p` con un pipe de stdin abierto puede esperar para siempre | Stdin se cierra con `</dev/null` |
| Una tarea que empieza con `/` llega a Cursor alterada | Git Bash reescribe argumentos que parecen rutas POSIX | `MSYS2_ARG_CONV_EXCL='*'` con rutas nativas construidas por `cygpath -m`. No `MSYS_NO_PATHCONV=1`: eso también deja de convertir variables de entorno con forma de ruta, y al heredarlo el delegado dejó al `git` nativo ciego a `GIT_CONFIG_GLOBAL` (lo atraparon los tests). El preload quita la variable dentro de Cursor, así que los comandos propios del delegado convierten rutas con normalidad (verificado) |
| Una ejecución en modo ask no edita nada e informa poco | El modo ask rechaza ediciones y rechazó comandos de shell | `--read-only` mapea a modo ask; pega diffs en la tarea |
| `[cursor-rescue] WARNING: …` tras una ejecución | El delegado movió `HEAD`, cambió de rama, o alteró la lista de stash, el git config o los hooks | `run` los compara antes y después e imprime una línea por cada cambio — revisa antes de tu próximo comando git |
| `[cursor-rescue] task is N characters, over the 30000 limit` (exit 64) | Toda la tarea viaja como un solo argumento de línea de comandos; Windows limita una línea de comandos a 32767 caracteres | Las tareas de más de 30000 caracteres se rechazan antes de que corra nada — referencia archivos por ruta o divide la tarea |
| `preflight failed: not signed in` (exit 70) | No se encontró inicio de sesión | Corre `cursor-agent login` una vez (o exporta `CURSOR_API_KEY`), luego `/cursor:setup` |
| `[cursor-rescue] Cursor quota or plan limit hit` | Límite de uso, rate limit, `429`, o cupo del plan agotado | El subagente se detiene y nunca reintenta — continúa inline o con otro delegado, y dilo una vez |
| `cursor-agent not found` (exit 127) | CLI no instalado o no en el PATH | Instálalo (ver Requisitos), luego `/cursor:setup` |
| `missing deny rules` (exit 78) | `~/.cursor-rescue/cli-config.json` ausente o incompleto | Corre `/cursor:setup` para recrearlo o repararlo |

Límites conocidos: aún sin passthrough de `--worktree` (`cursor-agent -w` crea
un git worktree aislado bajo `~/.cursor/worktrees/` — no verificado), y sin
indicador de cuota — el CLI no expone un comando de uso headless, así que la
detección de cuota es reactiva (ver la fila de cuota arriba).

## Con otros delegados

Este plugin no asume ningún orden entre delegados: si corres varios, define
los disparadores y fallbacks de cada uno en tu `CLAUDE.md`. Ante señales de
cuota, límite de uso o inicio de sesión, el subagente se detiene y las reporta,
para que quien llama elija otra vía. Proyectos relacionados del mismo autor,
sin ningún ranking:
[copilot-plugin-cc](https://github.com/santiquiroz/copilot-plugin-cc),
[antigravity-plugin-cc](https://github.com/santiquiroz/antigravity-plugin-cc),
[ollama-plugin-cc](https://github.com/santiquiroz/ollama-plugin-cc),
[bipolar-plugin-cc](https://github.com/santiquiroz/bipolar-plugin-cc) — todos
inspirados en [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc).

## Licencia

[MIT](LICENSE). **No está afiliado con Cursor (Anysphere), OpenAI, GitHub,
Google ni Anthropic.**
