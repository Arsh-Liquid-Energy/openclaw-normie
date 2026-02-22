import type { OpenClawConfig } from "../config/config.js";

/**
 * Starter skill keys — curated for consumer users.
 *
 * Selected for: no or widely-available binary deps, useful to non-technical
 * users, cross-platform where possible.  The `starterSet` flag causes
 * `shouldIncludeSkill()` to auto-include any of these whose runtime
 * requirements are met (binary present, env var set, etc.).
 */
export const STARTER_SKILL_KEYS: readonly string[] = [
  "weather",
  "summarize",
  "github",
  "session-logs",
  "canvas",
  "skill-creator",
  "healthcheck",
  "nano-pdf",
  "video-frames",
  "gifgrep",
  "openai-whisper-api",
  "openai-image-gen",
  "notion",
  "apple-notes",
  "apple-reminders",
  "goplaces",
] as const;

/** Set of starter keys for O(1) lookup. */
export const STARTER_SKILL_KEY_SET: ReadonlySet<string> = new Set(STARTER_SKILL_KEYS);

/**
 * Enable the starter-skill flag on the config so that
 * `shouldIncludeSkill()` auto-includes qualifying starter skills.
 */
export function applyDefaultStarterSkills(config: OpenClawConfig): OpenClawConfig {
  return {
    ...config,
    skills: {
      ...config.skills,
      starterSet: true,
    },
  };
}
