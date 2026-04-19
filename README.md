# tmux-projectizer

`tmux-projectizer` is a reusable tmux plugin that turns a set of project roots into quick session workflows. It picks a project directory, creates a predictable multi-window tmux session for it, and lets you jump back to any existing session with a fast picker.

It is extracted from a custom local tmux setup, generalized into TPM conventions, and packaged so it is ready to publish and install from GitHub.

## Features

- Scans one or more project roots for candidate directories.
- Creates project sessions on demand, or switches to an existing matching session.
- Builds a repeatable first-window layout plus additional named windows.
- Uses `fzf` inside a tmux popup when available.
- Tracks recently-used sessions and promotes them to the top of the session switcher.
- Opens a dedicated kill-session picker so you can remove old tmux sessions without leaving the keyboard.
- Falls back cleanly when popups or `fzf` are unavailable.
- Reads all behavior from tmux options, so it is easy to customize per machine.

## Requirements

- tmux 3.2+ for popup support.
- `fzf` is recommended for the project picker and session switcher.
- Without tmux popup support, `new-project-session` falls back to `command-prompt` and `switch-session` falls back to `choose-tree`.

## Installation

### TPM

Add the plugin to your `~/.tmux.conf`:

```tmux
set -g @plugin 'thehamsti/tmux-projectizer'
```

Then reload tmux and install with TPM:

```tmux
prefix + I
```

### Manual installation

Clone the repo somewhere tmux can read it:

```bash
git clone https://github.com/thehamsti/tmux-projectizer.git ~/.tmux/plugins/tmux-projectizer
```

Source the plugin from `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-projectizer/tmux-projectizer.tmux
```

Reload tmux:

```tmux
tmux source-file ~/.tmux.conf
```

## Usage

- `@projectizer-new-session-key` opens the project picker and creates or reuses a session for the selected directory.
- `@projectizer-switch-session-key` opens the session picker and switches to an existing tmux session.
- `@projectizer-kill-session-key` opens the kill-session picker and deletes the selected tmux session.

With the default bindings:

- `prefix + S` opens the project picker.
- `prefix + f` opens the session switcher.
- `prefix + X` opens the kill-session picker.
- `prefix + 1` through `prefix + 9` jump straight to the corresponding recent session.

When a new session is created:

1. The session name is derived from the selected directory basename and sanitized for tmux.
2. The first window is created with the configured split layout.
3. Extra windows are created from `@projectizer-windows`.
4. The configured initial window is selected.

## Configuration

All options use tmux global options and can be set in `~/.tmux.conf`.

| Option | Default | Description |
| --- | --- | --- |
| `@projectizer-paths` | `"$HOME/projects"` | Space-separated list of directories to search for projects |
| `@projectizer-search-depth` | `2` | Max depth for `find` when scanning project directories |
| `@projectizer-new-session-key` | `S` | Key binding for new project session picker |
| `@projectizer-switch-session-key` | `f` | Key binding for session switcher |
| `@projectizer-kill-session-key` | `X` | Key binding for the kill-session picker |
| `@projectizer-layout` | `"main-vertical"` | Layout for new sessions (`main-vertical`, `even-horizontal`, and other tmux layouts) |
| `@projectizer-main-pane-width` | `"66%"` | Main pane width for `main-*` layouts |
| `@projectizer-windows` | `"main bg logs"` | Space-separated window names to create |
| `@projectizer-initial-window` | `1` | 1-based ordinal of the created window to select after creation |
| `@projectizer-fzf-height` | `"40%"` | Height for the `fzf` popup |
| `@projectizer-popup` | `"auto"` | `"auto"` uses popup when available, `"always"` requires popup, `"never"` disables popup fallbacks |
| `@projectizer-history-size` | `50` | Max number of recent sessions to keep in the history file |
| `@projectizer-history-file` | `"$HOME/.tmux/projectizer-recent"` | File that stores recent sessions, one session name per line |
| `@projectizer-quick-switch` | `"on"` | `"on"` binds `prefix + 1` through `prefix + 9` to recent sessions, `"off"` leaves number keys alone |

Example configuration:

```tmux
set -g @projectizer-paths "$HOME/projects $HOME/k16"
set -g @projectizer-search-depth 3
set -g @projectizer-layout "main-vertical"
set -g @projectizer-main-pane-width "70%"
set -g @projectizer-windows "main editor logs scratch"
set -g @projectizer-initial-window 2
set -g @projectizer-new-session-key "S"
set -g @projectizer-switch-session-key "f"
set -g @projectizer-kill-session-key "X"
set -g @projectizer-history-size 75
set -g @projectizer-history-file "$HOME/.tmux/projectizer-recent"
set -g @projectizer-quick-switch "on"
```

## Recent Sessions

Every time `tmux-projectizer` creates a session, reuses one from the project picker, or switches to one from the session switcher, it records that session in a recent-history file.

The default history file is:

```bash
$HOME/.tmux/projectizer-recent
```

The file format is intentionally simple:

```text
hamsti-lms
aisdk-template-nextjs
blog
my-app
```

- One session name per line
- Most recent session first
- Automatically deduplicated
- Truncated to `@projectizer-history-size`

When you open the session switcher with `prefix + f`, tmux-projectizer reads that file and orders the picker with recent sessions first, followed by the rest of your sessions alphabetically. That gives the switcher an alt-tab-like feel where your current working set stays at the top.

## Quick Switch

`prefix + 1` through `prefix + 9` provide direct "Nth most recent session" switching without opening the picker:

- `prefix + 1` switches to the most recent session
- `prefix + 2` switches to the second most recent session
- and so on through `prefix + 9`

Quick switch reads the same recent-session history file used by the session picker. If a slot is empty or points to a session that no longer exists, tmux-projectizer shows a short message instead of failing.

You can disable the bindings entirely:

```tmux
set -g @projectizer-quick-switch "off"
```

Tradeoff: tmux uses `prefix + 0-9` for window-by-index selection by default. When quick switch is on, tmux-projectizer replaces `prefix + 1` through `prefix + 9` with recent-session switching. If you prefer the default tmux window bindings, set `@projectizer-quick-switch` to `"off"`.

## Per-Project Configuration

If a selected project directory contains a `.tmux-projectizer.yml` file, the plugin reads it before creating the tmux session and uses those values as project-local overrides.

Precedence order:

1. Global tmux options like `@projectizer-windows`
2. Environment variables passed by the plugin entry point
3. `.tmux-projectizer.yml` in the selected project directory

Supported YAML keys:

| YAML key | Overrides |
| --- | --- |
| `windows` | `@projectizer-windows` |
| `layout` | `@projectizer-layout` |
| `main_pane_width` | `@projectizer-main-pane-width` |
| `initial_window` | `@projectizer-initial-window` |
| `search_depth` | `@projectizer-search-depth` |

The parser is intentionally simple and dependency-free. Use a flat structure with scalar values and a `windows` list made of consecutive `- name: ...` entries. Project-local windows can also define an optional `command:` that is sent to the window after it is created.

Startup commands are only available in `.tmux-projectizer.yml`. The global `@projectizer-windows` tmux option stays a plain list of window names.

Example:

```yaml
windows:
  - name: editor
  - name: server
    command: npm run dev
  - name: logs
    command: docker compose logs -f
layout: main-vertical
main_pane_width: 70%
initial_window: 2
```

For example, a Next.js app might keep its project-local workflow alongside the code:

```yaml
# my-next-app/.tmux-projectizer.yml
windows:
  - name: editor
  - name: dev
    command: npm run dev
  - name: logs
    command: docker compose logs -f
  - name: tests
    command: npm test -- --watch
layout: main-vertical
main_pane_width: 72%
initial_window: 2
```

With that file in place, selecting `my-next-app` creates an `editor` workspace window, then dedicated `dev`, `logs`, and `tests` windows, regardless of the global defaults configured in your tmux config. The `dev`, `logs`, and `tests` windows immediately start their configured commands after creation.

## How the picker behaves

- `new-project-session` uses popup + `fzf` when tmux and `fzf` support it.
- If popup support is unavailable, it falls back to `command-prompt` so you can type a directory path manually.
- `switch-session` uses popup + `fzf` when possible, otherwise it falls back to tmux `choose-tree`.
- `kill-session` uses the same popup + recent ordering as the switcher, but excludes the current session so you cannot delete the session you are standing in.
- Without popup + `fzf`, `kill-session` falls back to `choose-tree` and shows a note that deletion is not available in fallback mode.
- Canceling either picker exits cleanly without disrupting the current client.

## Similar plugins

- [`tmux-sessionist`](https://github.com/tmux-plugins/tmux-sessionist) for quick session and window shortcuts.
- [`tmuxinator`](https://github.com/tmuxinator/tmuxinator) for declarative project session bootstrapping.

`tmux-projectizer` sits between those tools: lighter-weight than a full project orchestrator, but more opinionated than a bare session switcher.

## License

Released under the MIT License. See [`LICENSE`](./LICENSE).
