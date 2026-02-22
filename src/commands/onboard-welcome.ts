/**
 * Welcome message for first-time users.
 *
 * Instead of proactively sending a message (which requires a target chat ID
 * that we don't have during onboarding), we inject a system instruction into
 * the AI's first-turn context via `prependSystemEvents()`.  The AI weaves
 * the welcome naturally into its first response.
 *
 * Triggered when `config.skills.starterSet === true` and the session is new.
 */

/**
 * System instruction prepended on the AI's first turn with a new user.
 *
 * The AI is told to open with a friendly welcome, mention key capabilities,
 * and then answer the user's actual question — all in one response.
 */
export const WELCOME_SYSTEM_INSTRUCTION = [
  "[First-time user — welcome them]",
  "This is the user's very first message to you.",
  "Start your response with a short, warm welcome (2-3 sentences).",
  "Briefly mention a few things you can help with:",
  "answering questions, summarizing links, writing and editing text,",
  "weather, reminders, notes, web search, and code tasks.",
  "Then answer their actual message below.",
  "Keep the welcome concise — don't overwhelm them.",
].join(" ");
