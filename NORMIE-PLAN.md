# OpenClaw "Normie Edition" — Implementation Plan

> Fork goal: Make OpenClaw installable and usable by non-technical people in under 5 minutes, with zero configuration decisions beyond "pick your messaging app."

---

## 1. ONE-LINE INSTALLER (`install.sh`)

### New file: `/install.sh` (project root)

A standalone bash script invoked via:

```bash
curl -fsSL https://raw.githubusercontent.com/<fork>/openclaw/main/install.sh | bash
```

**What it must do (in order):**

1. **Detect OS and architecture**
   - `uname -s` → Darwin / Linux
   - `uname -m` → x86_64 / arm64 / aarch64
   - Reject Windows (print "use WSL" message and exit)

2. **Check for Node.js >= 22.12.0**
   - If `node` not found or version < 22.12: install silently
   - **macOS:** Use the official Node.js binary tarball from `https://nodejs.org/dist/` (no Homebrew dependency). Download, extract to `~/.local/share/openclaw/node/`, prepend to PATH, write a line to `~/.bashrc` / `~/.zshrc`
   - **Linux:** Same tarball approach, or use NodeSource setup script (`https://deb.nodesource.com/setup_22.x`) if apt is available
   - Never prompt the user. All output should be single-line progress messages (`Installing Node.js 22...`)

3. **Install OpenClaw globally**
   - `npm install -g openclaw@latest` (using the freshly-installed or existing Node)
   - Suppress npm audit/fund noise: `--no-audit --no-fund --loglevel=error`

4. **Run simplified onboarding automatically**
   - `openclaw onboard --flow quickstart --accept-risk --skip-skills --skip-hooks`
   - But we'll modify what `--flow quickstart` does (see Section 2 below), so this single command triggers the new simplified wizard

5. **Print a single success line**
   - `OpenClaw is ready! Check your Telegram/WhatsApp for a welcome message.`

### File to modify: `/package.json`

- Add `"install-script": "install.sh"` to `files` array so it's included in npm package
- No other changes needed here

---

## 2. SIMPLIFIED ONBOARDING

### Overview of changes

The existing quickstart flow already skips many prompts. We modify it further so the user path is:

```
Security ack → Auth setup → Connect Telegram or WhatsApp → Done
```

Everything else uses sensible defaults (gateway on loopback:8000 with token auth, default workspace, auto-enabled starter skills, daemon auto-installed).

---

### File: `src/wizard/onboarding.ts` (main wizard orchestrator)

**Current flow (lines ~60-180):**

```
1. printWizardHeader
2. Risk acknowledgement
3. Load/validate existing config
4. Flow selection (quickstart vs advanced)
5. Mode selection (local vs remote)
6. Workspace directory prompt
7. Auth + model config
8. Gateway config (configureGatewayForOnboarding)
9. Channel setup (setupChannels)
10. Skills setup (setupSkills)
11. Hooks setup (setupInternalHooks)
12. Write config
13. finalizeOnboardingWizard
```

**Changes:**

- After step 2 (risk ack), if `flow === "quickstart"`:
  - **Skip step 4** (flow selection) — already quickstart
  - **Skip step 5** (mode selection) — hardcode `mode = "local"`
  - **Skip step 6** (workspace prompt) — use default `~/.openclaw/workspace`
  - **Step 7** (auth): Keep, but reorder choices (see below)
  - **Skip step 8** (gateway config) — use quickstart defaults already in `configureGatewayForOnboarding` (loopback, port 8000, token auth, tailscale off)
  - **Step 9** (channels): Keep, but modify to be a single pick (see below)
  - **Skip step 10** (skills) — auto-apply starter set instead (see Section 4)
  - **Skip step 11** (hooks) — use defaults
  - **Step 12 & 13**: Keep (write config + finalize)

**Specific code change:** In `runOnboardingWizard()`, after risk acknowledgement and before auth setup, add an early-exit block for quickstart that:

1. Sets workspace to default
2. Calls auth setup (modified)
3. Calls channel setup (modified, single-pick mode)
4. Calls `applyDefaultStarterSkills(nextConfig)` (new helper)
5. Writes config
6. Calls `finalizeOnboardingWizard` with `skipHealth: false, skipUi: false`
7. Sends welcome message (new step — see Section 3)

---

### File: `src/wizard/onboarding.ts` — Simplify security warning text

**Current text (lines 29-52):**

```
Security warning — please read.

OpenClaw is a hobby project and still in beta. Expect sharp edges.
This bot can read files and run actions if tools are enabled.
A bad prompt can trick it into doing unsafe things.
...
(long detailed text with CLI commands)
```

**Replace with (for quickstart flow only):**

```
Heads up — OpenClaw is an AI agent that can take real actions on your
computer and messaging apps. It's powerful, but that means you should
only give it access to things you're comfortable with.

We've set safe defaults, but keep an eye on what it does at first.
```

**Confirmation prompt stays:** "I understand. Let's go." (simplified from current wording)

**How:** Add a conditional in the risk acknowledgement section — if `flow === "quickstart"`, show the short version. The existing detailed version stays for `advanced`/`manual` flows.

---

### File: `src/commands/auth-choice-options.ts` — Reorder auth choices

**Current order (line 24+):**

1. OpenAI (Codex OAuth + API key)
2. Anthropic (setup-token + API key)
3. Chutes
4. ... (23 more groups)

**Change:** OpenAI is already first — no reorder needed. But modify the **presentation** for quickstart:

- In quickstart mode, show only the top 4 groups initially:
  1. **OpenAI** — "Sign in with your ChatGPT account" (relabel `openai-codex` hint)
  2. **Anthropic** — "Use your Claude account"
  3. **Google Gemini** — "Use your Google account"
  4. **Show more options...** (expands to full list)

**File to modify:** `src/commands/auth-choice-options.ts`

- Add a `quickstart?: boolean` field to `AUTH_CHOICE_GROUP_DEFS` entries for the top 4
- Export a `QUICKSTART_AUTH_GROUPS` filtered list

**File to modify:** `src/wizard/onboarding.ts` (or wherever auth choice is rendered)

- When `flow === "quickstart"`, use `QUICKSTART_AUTH_GROUPS` for the initial prompt
- Add a "More options" escape hatch that shows the full list

**File to modify:** `src/commands/auth-choice-options.ts` — relabel hints

- `openai-codex` hint: change from current text → `"Recommended — sign in with your ChatGPT account (no API key needed)"`
- `token` (Anthropic setup-token) hint: → `"Sign in with your Claude account"`
- `gemini-api-key` hint: → `"Use your Google Gemini API key"`

---

### File: `src/commands/onboard-channels.ts` — Simplify channel selection

**Current behavior:**

- Shows full channel catalog (Discord, Slack, Telegram, Signal, WhatsApp, Matrix, iMessage, etc.)
- Loops: user can add multiple channels
- Prompts for DM policies, group policies, etc.

**Changes for quickstart flow:**

Replace the loop with a single prompt:

```
How do you want to talk to your AI?

  ❯ Telegram (recommended — easiest setup)
    WhatsApp
    Skip for now
```

After selection:

- **Telegram path:** Trigger existing `telegramOnboardingAdapter` from `src/channels/plugins/onboarding/telegram.ts`
  - Show: "Go to Telegram, message @BotFather, send /newbot, paste the token here:"
  - Accept token → configure `channels.telegram.botToken`
  - Set `dmPolicy: "open"` (for a personal bot, no pairing needed)
  - Skip group policy config entirely
- **WhatsApp path:** Trigger existing `whatsappOnboardingAdapter` from `src/channels/plugins/onboarding/whatsapp.ts`
  - Trigger QR code login flow (`loginWeb()`)
  - Set `dmPolicy: "open"`
  - Skip group policy config entirely
- **Skip:** Continue without channel (show note: "You can add one later with `openclaw channels setup`")

**Specific changes in `src/commands/onboard-channels.ts`:**

- Add an `if (options?.quickstartDefaults)` branch at the top of `setupChannels()`
- This branch shows the simplified 3-option prompt
- Calls the appropriate onboarding adapter with simplified options (no DM policy prompt, no group config)
- Returns immediately after one channel is configured

**Also modify:** `src/channels/plugins/onboarding/telegram.ts`

- Add a `simplified?: boolean` option to the adapter
- When simplified: skip the "fetch user ID" step, skip allowFrom setup, skip DM policy prompt
- Just: get token → validate → save → done

**Also modify:** `src/channels/plugins/onboarding/whatsapp.ts`

- Add a `simplified?: boolean` option to the adapter
- When simplified: skip phone mode selection, skip DM policy prompt
- Just: QR scan → link → save → done

---

### File: `src/wizard/onboarding.gateway-config.ts` — No changes needed

The existing quickstart flow already applies sensible defaults:

- Port: 8000
- Bind: loopback (127.0.0.1)
- Auth: token (auto-generated)
- Tailscale: off

These are correct for a consumer user. The quickstart path in `configureGatewayForOnboarding` already handles this — we just need to make sure it's called with quickstart settings, which it already is.

---

### File: `src/commands/onboard-skills.ts` — Skip entirely for quickstart

**Current behavior:** Prompts user to review eligible/missing skills and install deps.

**Change:** In `runOnboardingWizard()`, when `flow === "quickstart"`, do NOT call `setupSkills()`. Instead call `applyDefaultStarterSkills()` (see Section 4).

No changes to `onboard-skills.ts` itself — it stays for `advanced` mode.

---

### File: `src/commands/onboard-hooks.ts` — Skip entirely for quickstart

**Current behavior:** Prompts for which hooks to enable.

**Change:** In `runOnboardingWizard()`, when `flow === "quickstart"`, skip `setupInternalHooks()`. Use whatever defaults the system already applies.

No changes to `onboard-hooks.ts` itself.

---

### File: `src/wizard/onboarding.finalize.ts` — Minor changes

**Current behavior:** Offers hatch options (TUI / Web UI / Later), shows docs links, etc.

**Changes for quickstart:**

- Skip the "hatch" prompt — auto-install daemon and start gateway
- After gateway is confirmed reachable, trigger welcome message (see Section 3)
- Show a single closing message instead of the current multi-paragraph notes:

  ```
  You're all set! Your AI agent is running.
  Check your [Telegram/WhatsApp] — it just sent you a hello.

  To chat with it here in the terminal: openclaw tui
  To stop it:                           openclaw gateway stop
  To reconfigure:                       openclaw configure
  ```

---

## 3. WELCOME MESSAGE

### New file: `src/commands/onboard-welcome.ts`

A new module that sends a welcome message after onboarding completes and the gateway is running.

**Function signature:**

```typescript
export async function sendWelcomeMessage(opts: {
  channel: "telegram" | "whatsapp";
  target: string; // Telegram chat ID or WhatsApp phone number
  accountId?: string; // For multi-account setups
  gatewayUrl: string; // e.g. "http://127.0.0.1:8000"
  gatewayToken: string;
}): Promise<void>;
```

**Implementation:**

- Use the existing `sendMessage()` from `src/infra/outbound/message.ts`
- Or use the CLI equivalent: spawn `openclaw message send --channel <channel> --target <target> --message <text>`
- The CLI approach is simpler and doesn't require importing gateway internals

**When to call it:**

- In `src/wizard/onboarding.finalize.ts`, after `waitForGatewayReachable()` succeeds
- Only if a channel was configured during onboarding
- Pass the channel type and target (Telegram chat ID or WhatsApp phone number) from the onboarding state

**The welcome message:**

```
Hey! I'm your OpenClaw AI agent, and I'm ready to help.

You can talk to me just like you'd talk to a friend. Here are some things I can do:

- Answer questions about anything
- Summarize articles, videos, or podcasts (just send me a link)
- Help you write and edit text
- Look up the weather, places, and directions
- Set reminders and manage your notes
- Search the web for you
- Help with code and technical tasks

Just send me a message whenever you need something. I'll do my best to help.

A few tips:
- Be specific about what you want — the clearer you are, the better I'll do
- I can handle follow-up questions, so feel free to have a conversation
- If I get something wrong, just tell me and I'll fix it

Let's get started — what can I help you with?
```

**How to pass the target from onboarding to finalization:**

Modify `runOnboardingWizard()` to track which channel was configured and the user's identifier:

```typescript
// After channel setup completes, capture:
const channelResult = {
  channel: "telegram" | "whatsapp" | null,
  target: string | null, // chat ID or phone number
  accountId: string | null,
};
```

Pass this into `finalizeOnboardingWizard()` via a new field on `FinalizeOnboardingOptions`.

---

## 4. DEFAULT SKILLS — Starter Set

### New file: `src/commands/onboard-default-skills.ts`

**Function:**

```typescript
export function applyDefaultStarterSkills(config: OpenClawConfig): OpenClawConfig;
```

This function sets `config.skills.entries[skillKey].enabled = true` for the starter set, and leaves everything else at its default (which is also enabled, but won't load if requirements aren't met).

### Recommended starter set (16 skills)

Selected for: no binary dependencies OR widely-available deps (`curl`, `jq`), no API keys required, useful to non-technical users, cross-platform where possible.

| #   | Skill                  | Why                                                      | Requires                                                    |
| --- | ---------------------- | -------------------------------------------------------- | ----------------------------------------------------------- |
| 1   | **weather**            | Everyone checks weather. No API key.                     | `curl` (universal)                                          |
| 2   | **summarize**          | Send a link, get a summary. Huge value.                  | `summarize` binary (install via brew/npm)                   |
| 3   | **github**             | Browse repos, issues, PRs for anyone technical-adjacent. | `gh` (install via brew/npm)                                 |
| 4   | **session-logs**       | Search old conversations. Useful immediately.            | `jq`, `rg` (common)                                         |
| 5   | **canvas**             | Display rich HTML on connected devices.                  | None                                                        |
| 6   | **skill-creator**      | Guidance for making custom skills.                       | None                                                        |
| 7   | **healthcheck**        | Security auditing built-in.                              | None                                                        |
| 8   | **nano-pdf**           | Edit PDFs with natural language.                         | `nano-pdf` (install via uv)                                 |
| 9   | **video-frames**       | Extract frames from videos.                              | `ffmpeg` (common)                                           |
| 10  | **gifgrep**            | Search and send GIFs. Fun and useful in chat.            | `gifgrep` binary                                            |
| 11  | **openai-whisper-api** | Transcribe voice messages. Key for messaging.            | `curl`, `OPENAI_API_KEY` (already set if using OpenAI auth) |
| 12  | **openai-image-gen**   | Generate images from text.                               | `python3`, `OPENAI_API_KEY`                                 |
| 13  | **notion**             | Notes and docs for Notion users.                         | `NOTION_API_KEY`                                            |
| 14  | **apple-notes**        | Notes for macOS users. Zero setup.                       | `memo` binary, macOS only                                   |
| 15  | **apple-reminders**    | Reminders for macOS users.                               | `remindctl`, macOS only                                     |
| 16  | **goplaces**           | Look up restaurants, businesses, directions.             | `goplaces`, `GOOGLE_PLACES_API_KEY`                         |

**Implementation strategy:**

Rather than force-enabling specific skills (which would fail if requirements aren't met), set a `config.skills.starterSet = true` flag that:

1. On first gateway boot, evaluates which starter skills have their requirements met
2. Auto-enables those that do
3. Shows a one-time note in the TUI/channel: "I've enabled X skills that work on your system: weather, summarize, ..."

**File to modify:** `src/agents/skills/config.ts`

- In `shouldIncludeSkill()`, if `config.skills.starterSet === true` and the skill is in the starter list and requirements are met → include it
- This is passive — doesn't install anything, just enables what's already available

**File to modify:** `src/config/types.skills.ts`

- Add `starterSet?: boolean` to `SkillsConfig` type

**File to create:** `src/commands/onboard-default-skills.ts`

- Export `STARTER_SKILL_KEYS: string[]` — the list of 16 skill keys above
- Export `applyDefaultStarterSkills(config)` — sets `config.skills.starterSet = true`

---

## 5. COMPLETE FILE CHANGE SUMMARY

### New files to create

| File                                     | Purpose                                   |
| ---------------------------------------- | ----------------------------------------- |
| `/install.sh`                            | One-line installer script                 |
| `src/commands/onboard-welcome.ts`        | Welcome message sender                    |
| `src/commands/onboard-default-skills.ts` | Starter skill set definition + applicator |

### Files to modify

| File                                          | Change                                                                                                                                               |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/wizard/onboarding.ts`                    | Add simplified quickstart branch: skip workspace/gateway/skills/hooks prompts, add welcome message trigger, simplify security warning for quickstart |
| `src/wizard/onboarding.finalize.ts`           | For quickstart: auto-install daemon (no prompt), call `sendWelcomeMessage()` after gateway is reachable, show simplified completion message          |
| `src/commands/auth-choice-options.ts`         | Add `quickstart` flag to top 4 auth groups, export `QUICKSTART_AUTH_GROUPS`, relabel OpenAI/Anthropic/Gemini hints for consumer language             |
| `src/commands/onboard-channels.ts`            | Add quickstart branch: single Telegram/WhatsApp/Skip prompt, call adapter in simplified mode, return channel+target info                             |
| `src/channels/plugins/onboarding/telegram.ts` | Add `simplified?: boolean` option: skip user ID fetch, skip allowFrom, skip DM policy prompt, just get token and save                                |
| `src/channels/plugins/onboarding/whatsapp.ts` | Add `simplified?: boolean` option: skip phone mode, skip DM policy, just QR link and save                                                            |
| `src/agents/skills/config.ts`                 | In `shouldIncludeSkill()`: honor `starterSet` flag for starter skills with met requirements                                                          |
| `src/config/types.skills.ts`                  | Add `starterSet?: boolean` to `SkillsConfig`                                                                                                         |
| `src/commands/onboard-types.ts`               | Add `channelResult?: { channel, target, accountId }` to types passed through wizard                                                                  |
| `package.json`                                | Add `install.sh` to `files` array                                                                                                                    |

### Files that need NO changes

| File                                      | Why                                                             |
| ----------------------------------------- | --------------------------------------------------------------- |
| `src/wizard/onboarding.gateway-config.ts` | Quickstart defaults already correct (loopback:8000, token auth) |
| `src/commands/onboard-skills.ts`          | Not called in quickstart — stays for advanced mode              |
| `src/commands/onboard-hooks.ts`           | Not called in quickstart — stays for advanced mode              |
| `openclaw.mjs`                            | Entry point unchanged                                           |
| `src/entry.ts`                            | CLI bootstrap unchanged                                         |
| `src/cli/run-main.ts`                     | Command routing unchanged                                       |

---

## 6. USER EXPERIENCE WALKTHROUGH

What the full flow looks like after all changes:

```
$ curl -fsSL https://get.openclaw.dev/install.sh | bash

  Installing Node.js 22...  done
  Installing OpenClaw...    done
  Starting setup...

  ──────────────────────────────────────────────

  Heads up — OpenClaw is an AI agent that can take real
  actions on your computer and messaging apps. It's powerful,
  but that means you should only give it access to things
  you're comfortable with.

  We've set safe defaults, but keep an eye on what it does at first.

  ❯ I understand. Let's go.

  ──────────────────────────────────────────────

  How do you want to sign in?

  ❯ OpenAI — Sign in with your ChatGPT account (recommended)
    Anthropic — Sign in with your Claude account
    Google Gemini — Use your Gemini API key
    More options...

  (user picks OpenAI, completes OAuth)

  ──────────────────────────────────────────────

  How do you want to talk to your AI?

  ❯ Telegram (recommended — easiest setup)
    WhatsApp
    Skip for now

  (user picks Telegram)

  Go to Telegram → @BotFather → /newbot → paste token here:
  > 123456:ABCdefGHIjklMNO

  ✓ Bot connected: @MyOpenClawBot

  ──────────────────────────────────────────────

  Starting your agent...  done

  ✓ You're all set! Your AI agent is running.
    Check your Telegram — it just sent you a hello.

    To chat here in terminal:  openclaw tui
    To stop it:                openclaw gateway stop
    To reconfigure:            openclaw configure
```

Total time: ~2 minutes. Zero config files edited manually. Zero technical decisions.
