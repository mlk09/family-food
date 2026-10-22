// Prompts and JSON schemas for Chef AI. Kept separate so they can be unit-tested
// and tuned without touching transport code.

export type Ctx = {
  ingredients?: { name: string; quantity?: string; days_left?: number }[];
  profile?: {
    age_group?: string;
    diet?: string;
    allergies?: string[];
    preferences?: string[];
    favorites?: string[];
    dislikes?: string[];
    spice_level?: number;
  };
  saved_recipes?: string[];
  meal_plan?: string[];
  family_size?: number;
};

const SPICE = ["no spice", "mild", "medium", "spicy", "extra hot"];

// deno-lint-ignore no-control-regex
const clip = (s: unknown, n: number) => String(s ?? "").replace(/[\u0000-\u001f]/g, " ").slice(0, n);
const list = (a: unknown, maxItems: number, maxLen = 40) =>
  (Array.isArray(a) ? a : []).slice(0, maxItems).map((x) => clip(x, maxLen)).filter(Boolean);

/** Turns untrusted client context into a compact, bounded text block. */
export function describeContext(ctx: Ctx = {}): string {
  const p = ctx.profile ?? {};
  const ings = (Array.isArray(ctx.ingredients) ? ctx.ingredients : []).slice(0, 60).map((i) => {
    const d = typeof i?.days_left === "number" ? (i.days_left <= 2 ? ` (use soon: ${i.days_left}d left)` : "") : "";
    return `${clip(i?.name, 40)}${i?.quantity ? ` – ${clip(i.quantity, 20)}` : ""}${d}`;
  });
  const allergies = list(p.allergies, 15);
  return [
    `Kitchen ingredients: ${ings.length ? ings.join("; ") : "none listed"}.`,
    `Diet: ${clip(p.diet || "not specified", 20)}.`,
    `Allergies (NEVER include these or their derivatives): ${allergies.length ? allergies.join(", ") : "none listed"}.`,
    `Age group of user: ${clip(p.age_group || "adult", 10)}.`,
    `Spice preference: ${SPICE[Math.max(0, Math.min(4, Number(p.spice_level ?? 2)))]}.`,
    `Likes: ${list(p.favorites, 10).join(", ") || "-"}. Dislikes (avoid): ${list(p.dislikes, 10).join(", ") || "-"}.`,
    `Cuisine/food preferences: ${list(p.preferences, 10).join(", ") || "-"}.`,
    ctx.family_size ? `Family size: ${Math.min(50, Number(ctx.family_size))}.` : "",
    list(ctx.saved_recipes, 15, 60).length ? `Family favourite recipes: ${list(ctx.saved_recipes, 15, 60).join(", ")}.` : "",
    list(ctx.meal_plan, 21, 80).length ? `This week's meal plan: ${list(ctx.meal_plan, 21, 80).join("; ")}.` : "",
  ].filter(Boolean).join("\n");
}

export function systemPrompt(ctx: Ctx = {}): string {
  const child = ctx.profile?.age_group === "child";
  return `You are "Chef AI", a warm, practical home-cooking assistant for families (often Indian households, but any cuisine is welcome).
Rules:
- Only help with cooking, food, recipes, ingredients, meal planning, groceries, kitchen safety and food storage. Politely decline anything else.
- Strictly respect the diet. Vegetarian: no meat/fish/eggs. Eggetarian: eggs ok, no meat/fish. Vegan: no animal products. Jain: no meat/fish/eggs, no onion, garlic, potato or other root vegetables.
- NEVER include listed allergens. If a request conflicts with an allergy, say so and offer a safe alternative.
- Do not make medical or health-treatment claims. Nutrition numbers are rough estimates.
- Prefer ingredients the family already has, especially those marked "use soon". Assume salt, oil, water and basic Indian spices are available.
- Use simple, friendly language that children and elderly people can follow. Keep steps short.
- Reply in the same language and script the user writes in (Hindi in Devanagari, Hinglish in Roman letters, or English). Recipe names may stay in their common form.
- Include safety reminders for knives, hot oil, gas stoves, ovens, pressure cookers and boiling water.${child ? "\n- The user is a CHILD: keep everything simple and mild, and always say a grown-up must help with knives, heat and appliances." : ""}
- Never produce inappropriate, unsafe or non-food content.

Family context:
${describeContext(ctx)}`;
}

// ── JSON Schemas (OpenAI structured outputs, strict mode) ──

const str = { type: "string" };
const int = { type: "integer" };
const strArr = { type: "array", items: str };

export const recipeSchema = {
  type: "object",
  additionalProperties: false,
  required: ["name", "description", "emoji", "prep_time", "cook_time", "servings", "difficulty", "ingredients",
    "instructions", "missing_ingredients", "nutrition", "substitutions", "tags", "safety_notes"],
  properties: {
    name: str,
    description: str,
    emoji: str,
    prep_time: int,
    cook_time: int,
    servings: int,
    difficulty: { type: "string", enum: ["Easy", "Medium", "Hard"] },
    ingredients: {
      type: "array",
      items: {
        type: "object", additionalProperties: false, required: ["name", "quantity"],
        properties: { name: str, quantity: str },
      },
    },
    instructions: strArr,
    missing_ingredients: strArr,
    nutrition: {
      type: "object", additionalProperties: false, required: ["calories", "protein", "carbs", "fat"],
      properties: { calories: int, protein: int, carbs: int, fat: int },
    },
    substitutions: {
      type: "array",
      items: {
        type: "object", additionalProperties: false, required: ["ingredient", "substitute"],
        properties: { ingredient: str, substitute: str },
      },
    },
    tags: strArr,
    safety_notes: strArr,
  },
};

const wrap = (name: string, props: Record<string, unknown>) => ({
  name,
  strict: true,
  schema: { type: "object", additionalProperties: false, required: Object.keys(props), properties: props },
});

export const schemas = {
  generate_recipes: wrap("recipes", { recipes: { type: "array", items: recipeSchema } }),
  recipe_detail: wrap("recipe", { recipe: recipeSchema }),
  meal_plan: wrap("meal_plan", {
    days: {
      type: "array",
      items: {
        type: "object", additionalProperties: false, required: ["day", "meals"],
        properties: {
          day: { type: "integer", description: "0 = Monday … 6 = Sunday" },
          meals: {
            type: "array",
            items: {
              type: "object", additionalProperties: false,
              required: ["meal_type", "recipe_name", "emoji", "description", "ingredients"],
              properties: {
                meal_type: { type: "string", enum: ["breakfast", "lunch", "dinner"] },
                recipe_name: str, emoji: str, description: str, ingredients: strArr,
              },
            },
          },
        },
      },
    },
  }),
  substitutions: wrap("substitutions", {
    substitutions: {
      type: "array",
      items: {
        type: "object", additionalProperties: false, required: ["ingredient", "substitute"],
        properties: { ingredient: str, substitute: str },
      },
    },
  }),
  shopping_list: wrap("shopping_list", {
    items: {
      type: "array",
      items: {
        type: "object", additionalProperties: false, required: ["name", "quantity", "category"],
        properties: {
          name: str, quantity: str,
          category: { type: "string", enum: ["vegetables", "fruits", "dairy", "meat", "eggs", "grains", "spices", "other"] },
        },
      },
    },
  }),
  scan_ingredients: wrap("scan", {
    ingredients: {
      type: "array",
      items: { type: "object", additionalProperties: false, required: ["name"], properties: { name: str } },
    },
  }),
} as const;

// deno-lint-ignore no-explicit-any
export function userPrompt(action: string, body: any): string {
  switch (action) {
    case "generate_recipes": {
      const n = Math.max(1, Math.min(6, Number(body.count) || 4));
      return `Suggest ${n} different recipes the family can cook now, using as many kitchen ingredients as possible (prioritise "use soon" items).
List any ingredients they don't have in missing_ingredients (ignore salt, oil, water and basic spices). Ingredient names must be plain names (e.g. "onion"), quantities separate.
Give 4-9 short steps each, per-serving nutrition estimates, 1-3 useful substitutions and relevant tags (kids, quick, healthy, budget, breakfast, lunch, dinner).
${clip(body.request, 300) ? `Extra request: ${clip(body.request, 300)}` : ""}`;
    }
    case "recipe_detail":
      return `Write the full recipe for "${clip(body.name, 80)}" for this family. Mark missing_ingredients based on their kitchen.`;
    case "meal_plan": {
      const p = body.plan ?? {};
      const meals = list(p.meals_per_day, 3, 10).filter((m) => ["breakfast", "lunch", "dinner"].includes(m));
      const days = Math.max(1, Math.min(7, Number(p.days) || 7));
      return `Create a ${days}-day meal plan (days ${Array.from({ length: days }, (_, i) => i).join(",")}, where 0 = Monday) with these meals each day: ${(meals.length ? meals : ["dinner"]).join(", ")}.
People: ${Math.max(1, Math.min(50, Number(p.people) || 4))}. Diet: ${clip(p.diet, 20) || "vegetarian"}. ${p.budget ? `Weekly budget: ₹${Number(p.budget)} — keep it affordable.` : ""}
${p.use_kitchen ? "Use ingredients from their kitchen where possible." : ""} ${clip(p.preferences, 300) ? `Preferences: ${clip(p.preferences, 300)}.` : ""}
Vary dishes across the week (no repeats). Keep descriptions under 12 words. List 3-8 key ingredients per meal (plain names).`;
    }
    case "substitutions":
      return `What can replace "${clip(body.ingredient, 40)}"${clip(body.recipe, 80) ? ` in ${clip(body.recipe, 80)}` : ""}? Give 2-4 practical home-kitchen substitutes with a short tip each, respecting diet and allergies.`;
    case "shopping_list":
      return `Make a shopping list for these meals: ${list(body.meals, 30, 80).join("; ")}. Exclude anything already in the kitchen and basic pantry staples. Use practical Indian grocery quantities.`;
    default:
      return "";
  }
}
