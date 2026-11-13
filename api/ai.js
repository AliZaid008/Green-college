// Vercel serverless function: forwards the page's AI requests to Groq.
// The API key stays on the server (set GROQ_API_KEY in the project's environment variables).
// Groq's API is OpenAI-compatible, so another provider works by changing AI_URL and AI_MODEL.
const AI_URL = process.env.AI_URL || "https://api.groq.com/openai/v1/chat/completions";
const AI_MODEL = process.env.AI_MODEL || "openai/gpt-oss-120b"; // check your provider's current model list

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });
  const key = process.env.GROQ_API_KEY;
  if (!key) return res.status(500).json({ error: "GROQ_API_KEY is not set" });

  // With sign-in turned on, only signed-in people may use the AI (protects the free quota).
  const SB = process.env.SUPABASE_URL, SBKEY = process.env.SUPABASE_ANON_KEY;
  if (SB && SBKEY) {
    const auth = req.headers.authorization || "";
    if (!auth.startsWith("Bearer ")) return res.status(401).json({ error: "sign in first" });
    try {
      const u = await fetch(SB.replace(/\/$/, "") + "/auth/v1/user", { headers: { authorization: auth, apikey: SBKEY } });
      if (!u.ok) return res.status(401).json({ error: "sign in first" });
    } catch (e) {
      return res.status(502).json({ error: "could not check sign-in" });
    }
  }

  const { messages, json } = req.body || {};
  if (!Array.isArray(messages) || !messages.length || messages.length > 30)
    return res.status(400).json({ error: "messages must be a short list" });
  const clean = messages
    .filter(m => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .map(m => ({ role: m.role, content: m.content.slice(0, 20000) }));

  const body = { model: AI_MODEL, messages: clean, temperature: 0.4, max_tokens: 900 };
  if (json) body.response_format = { type: "json_object" };

  try {
    const r = await fetch(AI_URL, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer " + key },
      body: JSON.stringify(body),
    });
    if (!r.ok) return res.status(r.status === 429 ? 429 : 502).json({ error: "provider error " + r.status });
    const data = await r.json();
    // Nothing is logged or stored here: the private chat promise depends on that.
    return res.status(200).json({ text: data?.choices?.[0]?.message?.content || "" });
  } catch (e) {
    return res.status(502).json({ error: "could not reach the AI provider" });
  }
}
