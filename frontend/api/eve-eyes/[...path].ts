import type { VercelRequest, VercelResponse } from '@vercel/node';

const UPSTREAM = 'https://eve-eyes.d0v.xyz';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const apiKey = process.env.EVE_EYES_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'EVE_EYES_API_KEY not configured' });
  }

  // req.url is "/api/eve-eyes/api/indexer/killmails?limit=20"
  // Strip the "/api/eve-eyes" prefix to get "/api/indexer/killmails?limit=20"
  const path = (req.url ?? '').replace(/^\/api\/eve-eyes/, '');
  const upstream = `${UPSTREAM}${path}`;

  try {
    const upstreamRes = await fetch(upstream, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `ApiKey ${apiKey}`,
      },
    });

    const body = await upstreamRes.text();
    res
      .status(upstreamRes.status)
      .setHeader('Content-Type', upstreamRes.headers.get('content-type') ?? 'application/json')
      .send(body);
  } catch {
    res.status(502).json({ error: 'Upstream request failed' });
  }
}
