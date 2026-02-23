# OpenClaw Normie Edition

A consumer-friendly fork of [OpenClaw](https://github.com/openclaw/openclaw) that makes it possible for non-technical people to install and use a personal AI agent in under 5 minutes.

## What's Different

Regular OpenClaw is powerful but expects you to be comfortable with config files, CLI flags, DM policies, gateway networking, and skill management. This fork adds a **quickstart layer** on top — same engine, zero decisions.

|                   | Regular OpenClaw                                                 | Normie Edition                                                        |
| ----------------- | ---------------------------------------------------------------- | --------------------------------------------------------------------- |
| **Install**       | Clone repo, install Node, configure manually                     | `curl -fsSL <url>/install.sh \| bash`                                 |
| **Onboarding**    | 13-step wizard with networking, auth, DM policies, skills, hooks | 4 steps: security ack, sign in, pick a channel, done                  |
| **Auth setup**    | 25+ provider groups, all visible                                 | Top 3 (OpenAI, Anthropic, Google) with "More options..." escape hatch |
| **Channel setup** | Full catalog, multi-channel loop, DM policy config               | Single pick: Telegram / WhatsApp / Skip                               |
| **Skills**        | Manual review and dependency install                             | 16 starter skills auto-enabled if their deps are present              |
| **Welcome**       | No first-contact experience                                      | AI greets new users with a friendly intro on first message            |
| **Daemon**        | Prompted for install + runtime choice                            | Auto-installed, no prompts                                            |
| **Gateway**       | Port, bind, auth, Tailscale all configurable                     | Defaults: loopback:8000, token auth, Tailscale off                    |

Everything from the advanced/manual flow is still there. Quickstart is additive — it doesn't remove any existing functionality.

## One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/arshnoor/openclaw/main/install.sh | bash
```

This will:

1. Detect your OS (macOS / Linux) and architecture (x64 / arm64)
2. Install Node.js 22 if needed (no Homebrew dependency — uses official tarballs)
3. Install OpenClaw globally via npm
4. Launch the simplified onboarding wizard

## The Quickstart Flow

```
Security notice (5 lines, not a wall of text)
  -> "I understand. Let's go."

Sign in
  -> OpenAI (recommended) / Anthropic / Google / More options...

Pick your channel
  -> Telegram (paste bot token) / WhatsApp (scan QR) / Skip

Done. Agent is running. Message your bot.
```

Total time: ~2 minutes. No config files edited. No technical decisions.

---

## Technical Changes

15 files changed across 4 areas. All changes are additive — existing advanced/manual mode code is untouched.

### 1. One-Line Installer

**New file: `install.sh`** (302 lines)

- Bash 3.2 compatible (macOS default)
- Detects OS via `uname -s` (Darwin/Linux), arch via `uname -m` (x64/arm64/aarch64)
- Rejects Windows with a "use WSL" message
- Installs Node.js 22.12.0 from official tarballs to `~/.local/share/openclaw/node/`
- Persists PATH in `.zshrc`/`.bashrc`/`.profile` with `# openclaw-managed-node` marker
- Falls back to managed Node install if system `npm -g` fails (permissions)
- Redirects stdin from `/dev/tty` for piped invocation (`curl | bash`)
- Runs `openclaw onboard --flow quickstart` after install

**Modified: `package.json`** — Added `install.sh` to the `files` array.

### 2. Simplified Onboarding

**`src/wizard/onboarding.ts`** (+45 lines)

- Quickstart security warning: 5-line consumer notice replacing the full security wall
- Passes `quickstart: true` to auth prompt for filtered provider list
- Captures channel selection via `onSelection` callback
- Calls `applyDefaultStarterSkills()` instead of prompting for skills
- Skips hooks setup in quickstart

**`src/commands/auth-choice-options.ts`** (+7 lines)

- Exports `QUICKSTART_AUTH_GROUP_IDS` — a Set of `["openai", "anthropic", "google"]`

**`src/commands/auth-choice-prompt.ts`** (+49 lines)

- When `quickstart: true`, shows only 3 consumer-labeled providers:
  - OpenAI: "Recommended — sign in with your ChatGPT account"
  - Anthropic: "Sign in with your Claude account"
  - Google Gemini: "Use your Google account"
- "More options..." falls through to the full provider list
- Auto-selects the simplest auth method per group (e.g. OAuth for OpenAI)

**`src/commands/onboard-channels.ts`** (+18 lines)

- Quickstart branch replaces the full channel catalog loop with a single prompt:
  - Telegram (recommended — easiest setup)
  - WhatsApp (uses QR code to link)
  - Skip for now

**`src/channels/plugins/onboarding/telegram.ts`** (+35 lines)

- Quickstart mode: checks `TELEGRAM_BOT_TOKEN` env, else prompts for token
- Sets `dmPolicy: "open"`, skips allowFrom, account selection, user ID fetch

**`src/channels/plugins/onboarding/whatsapp.ts`** (+31 lines)

- Quickstart mode: runs QR linking if not already linked, sets `dmPolicy: "open"`
- Skips phone mode selection, DM policy prompt, allowFrom config

**`src/wizard/onboarding.finalize.ts`** (+38 lines)

- Quickstart early-return after health check — skips hatch prompt, Control UI notes, workspace backup, security reminder, web search setup, and "What now" links
- Auto-installs daemon without prompting (already handled by existing quickstart logic)
- Shows simplified 5-line completion note with channel-specific next step
- Accepts `quickstartChannel` parameter to customize the completion message

### 3. Welcome Message

**New file: `src/commands/onboard-welcome.ts`** (27 lines)

- Exports `WELCOME_SYSTEM_INSTRUCTION` — a system-level instruction injected on first contact
- Tells the AI to open with a friendly welcome, mention capabilities, then answer the user's question
- Reactive approach: works even for Telegram where bots can't message users first

**`src/auto-reply/reply/session-updates.ts`** (+5 lines)

- In `prependSystemEvents()`: when `isNewSession && isMainSession && config.skills.starterSet === true`, appends the welcome instruction to the system context
- The AI sees it on the first turn and naturally includes a greeting in its response

### 4. Default Skills

**New file: `src/commands/onboard-default-skills.ts`** (45 lines)

- `STARTER_SKILL_KEYS`: 16 curated skills (weather, summarize, github, canvas, healthcheck, nano-pdf, video-frames, gifgrep, openai-whisper-api, openai-image-gen, notion, apple-notes, apple-reminders, goplaces, session-logs, skill-creator)
- `STARTER_SKILL_KEY_SET`: Set for O(1) lookup
- `applyDefaultStarterSkills()`: sets `config.skills.starterSet = true`

**`src/config/types.skills.ts`** (+2 lines)

- Added `starterSet?: boolean` to `SkillsConfig` type

**`src/agents/skills/config.ts`** (+6 lines)

- Imports `STARTER_SKILL_KEY_SET`
- In `shouldIncludeSkill()`: when `starterSet` is true and the skill is in the starter list, bypasses the `allowBundled` restriction
- Skills still must pass OS and runtime requirement checks — `starterSet` only overrides the allowlist gate
