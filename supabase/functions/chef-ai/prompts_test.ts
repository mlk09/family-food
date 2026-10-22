// deno test supabase/functions/chef-ai/prompts_test.ts
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { describeContext, schemas, systemPrompt, userPrompt } from "./prompts.ts";

// OpenAI strict mode: every object needs additionalProperties:false and all keys required.
// deno-lint-ignore no-explicit-any
function assertStrict(node: any, path = "$") {
  if (node?.type === "object") {
    assertEquals(node.additionalProperties, false, `${path} must set additionalProperties:false`);
    assertEquals([...node.required].sort(), Object.keys(node.properties).sort(), `${path} must require every property`);
    for (const [k, v] of Object.entries(node.properties)) assertStrict(v, `${path}.${k}`);
  }
  if (node?.type === "array") assertStrict(node.items, `${path}[]`);
}

Deno.test("all JSON schemas are valid for OpenAI strict mode", () => {
  for (const [name, s] of Object.entries(schemas)) {
    assertEquals(s.strict, true, name);
    assertStrict(s.schema, name);
  }
});

Deno.test("context includes allergies, diet and use-soon items", () => {
  const text = describeContext({
    ingredients: [{ name: "Tomato", quantity: "4", days_left: 1 }, { name: "Rice", quantity: "2 kg", days_left: 90 }],
    profile: { diet: "jain", allergies: ["peanuts"], spice_level: 1, age_group: "child" },
  });
  assertStringIncludes(text, "Tomato – 4 (use soon: 1d left)");
  assertStringIncludes(text, "NEVER include these or their derivatives): peanuts");
  assertStringIncludes(text, "Diet: jain");
  assertStringIncludes(text, "Spice preference: mild");
});

Deno.test("context is bounded and strips control characters (prompt-size safety)", () => {
  const many = Array.from({ length: 500 }, (_, i) => ({ name: `item${i}\u0000\u0007` + "x".repeat(200) }));
  const text = describeContext({ ingredients: many });
  assert(text.length < 4000, `context too long: ${text.length}`);
  // deno-lint-ignore no-control-regex
  assert(!/[\u0000-\u0008]/.test(text));
});

Deno.test("child profiles get extra supervision rule", () => {
  assertStringIncludes(systemPrompt({ profile: { age_group: "child" } }), "grown-up must help");
  assert(!systemPrompt({ profile: { age_group: "adult" } }).includes("grown-up must help"));
});

Deno.test("user prompts clamp counts and include the request", () => {
  assertStringIncludes(userPrompt("generate_recipes", { count: 99, request: "South Indian" }), "Suggest 6 different");
  assertStringIncludes(userPrompt("generate_recipes", { request: "South Indian" }), "Extra request: South Indian");
  const plan = userPrompt("meal_plan", { plan: { days: 3, meals_per_day: ["dinner", "hack"], people: 4, budget: 900 } });
  assertStringIncludes(plan, "3-day meal plan");
  assertStringIncludes(plan, "each day: dinner.");
  assertStringIncludes(plan, "₹900");
  assertEquals(userPrompt("nope", {}), "");
});
