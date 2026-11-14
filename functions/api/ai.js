export async function onRequest(context) {
  const { request, env } = context;
  const configured = Boolean(env.GEMINI_API_KEY);
  if (request.method === "GET") {
    return Response.json({ configured });
  }
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (!configured) {
    return Response.json({ error: "Gemini API key is not configured. Add GEMINI_API_KEY in Cloudflare Pages secrets." }, { status: 503 });
  }
  try {
    const body = await request.json();
    const prompt = typeof body.prompt === "string" ? body.prompt.trim() : "";
    if (!prompt) return Response.json({ error: "Prompt is required." }, { status: 400 });
    if (prompt.length > 24000) return Response.json({ error: "Request is too long. Shorten the input and try again." }, { status: 413 });
    const upstream = await fetch("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": env.GEMINI_API_KEY
      },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.7, maxOutputTokens: 8192 }
      })
    });
    const data = await upstream.json();
    if (!upstream.ok) {
      const message = data?.error?.message || "Gemini API request failed.";
      return Response.json({ error: message }, { status: upstream.status === 429 ? 429 : 502 });
    }
    const text = (data?.candidates?.[0]?.content?.parts || []).map(part => part.text || "").join("\n").trim();
    if (!text) return Response.json({ error: "Gemini returned no text. Please try again." }, { status: 502 });
    return Response.json({ text });
  } catch (error) {
    return Response.json({ error: error?.message || "Unexpected AI server error." }, { status: 500 });
  }
}
