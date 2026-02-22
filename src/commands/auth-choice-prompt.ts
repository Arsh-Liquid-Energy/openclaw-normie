import type { AuthProfileStore } from "../agents/auth-profiles.js";
import type { WizardPrompter } from "../wizard/prompts.js";
import { buildAuthChoiceGroups, QUICKSTART_AUTH_GROUP_IDS } from "./auth-choice-options.js";
import type { AuthChoice } from "./onboard-types.js";

const BACK_VALUE = "__back";
const MORE_VALUE = "__more__";

/** Consumer-friendly labels shown in quickstart mode. */
const QUICKSTART_OVERRIDES: Record<string, { label: string; hint: string }> = {
  openai: { label: "OpenAI", hint: "Recommended — sign in with your ChatGPT account" },
  anthropic: { label: "Anthropic", hint: "Sign in with your Claude account" },
  google: { label: "Google Gemini", hint: "Use your Google account" },
};

export async function promptAuthChoiceGrouped(params: {
  prompter: WizardPrompter;
  store: AuthProfileStore;
  includeSkip: boolean;
  quickstart?: boolean;
}): Promise<AuthChoice> {
  const { groups, skipOption } = buildAuthChoiceGroups(params);
  const availableGroups = groups.filter((group) => group.options.length > 0);

  // Quickstart: show only top providers with consumer-friendly labels.
  // If user picks "More options", fall through to the full list below.
  let showFullList = false;
  if (params.quickstart) {
    const quickstartGroups = availableGroups.filter((g) => QUICKSTART_AUTH_GROUP_IDS.has(g.value));
    const quickstartOptions = [
      ...quickstartGroups.map((g) => {
        const overrides = QUICKSTART_OVERRIDES[g.value];
        return {
          value: g.value,
          label: overrides?.label ?? g.label,
          hint: overrides?.hint ?? g.hint,
        };
      }),
      { value: MORE_VALUE, label: "More options..." },
      ...(skipOption ? [skipOption] : []),
    ];

    const selection = await params.prompter.select({
      message: "How do you want to sign in?",
      options: quickstartOptions,
    });

    if (selection === "skip") {
      return "skip";
    }
    if (selection !== MORE_VALUE) {
      const group = quickstartGroups.find((g) => g.value === selection);
      if (group && group.options.length > 0) {
        // Auto-select the first (simplest) auth method for quickstart
        return group.options[0].value;
      }
    }
    showFullList = true;
  }

  while (true) {
    const providerOptions = [
      ...availableGroups.map((group) => ({
        value: group.value,
        label: group.label,
        hint: group.hint,
      })),
      ...(skipOption ? [skipOption] : []),
    ];

    const providerSelection = (await params.prompter.select({
      message: showFullList ? "All providers" : "Model/auth provider",
      options: providerOptions,
    })) as string;

    if (providerSelection === "skip") {
      return "skip";
    }

    const group = availableGroups.find((candidate) => candidate.value === providerSelection);

    if (!group || group.options.length === 0) {
      await params.prompter.note(
        "No auth methods available for that provider.",
        "Model/auth choice",
      );
      continue;
    }

    if (group.options.length === 1) {
      return group.options[0].value;
    }

    const methodSelection = await params.prompter.select({
      message: `${group.label} auth method`,
      options: [...group.options, { value: BACK_VALUE, label: "Back" }],
    });

    if (methodSelection === BACK_VALUE) {
      continue;
    }

    return methodSelection as AuthChoice;
  }
}
