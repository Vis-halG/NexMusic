// nexMusic activity notifications, deployed as a Cloudflare Worker.
//
// The app POSTs {"title", "body"} with the signed-in user's Firebase ID token
// in the Authorization header. The Worker checks the token, then sends the
// notification through Firebase Cloud Messaging to every phone registered in
// the Firestore `pushTokens` collection, except the sender's own phones.
//
// Required secret: SERVICE_ACCOUNT, the JSON key of the Firebase project's
// service account (Project settings → Service accounts → Generate new private
// key). Keep it only in the Worker; never put it in the app.

const GOOGLE_KEYS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const SCOPES =
  'https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore';

let googleKeys = { keys: [], expiresAt: 0 };
let accessToken = { token: '', expiresAt: 0 };

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return reply({ error: 'Use POST.' }, 405);
    }
    let account;
    try {
      account = JSON.parse(env.SERVICE_ACCOUNT);
    } catch {
      return reply({ error: 'The SERVICE_ACCOUNT secret is missing or is not valid JSON.' }, 500);
    }
    const projectId = account.project_id;

    let senderUid;
    try {
      const header = request.headers.get('Authorization') || '';
      senderUid = await verifyIdToken(header.replace(/^Bearer\s+/i, ''), projectId);
    } catch {
      return reply({ error: 'Sign in to nexMusic first.' }, 401);
    }

    let input;
    try {
      input = await request.json();
    } catch {
      return reply({ error: 'The request body must be JSON.' }, 400);
    }
    const title = text(input.title, 100);
    const body = text(input.body, 300);
    if (!title) return reply({ error: 'A title is required.' }, 400);

    try {
      const token = await getAccessToken(account);
      const phones = (await listPhones(projectId, token)).filter(
        (phone) => phone.uid !== senderUid,
      );
      const results = await Promise.all(
        phones.map((phone) => notify(projectId, token, phone, title, body)),
      );
      return reply({ phones: phones.length, sent: results.filter(Boolean).length });
    } catch (error) {
      return reply({ error: String(error) }, 502);
    }
  },
};

async function notify(projectId, token, phone, title, body) {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: {
          token: phone.token,
          notification: { title, body },
          android: {
            priority: 'HIGH',
            // The channel is created by the app (NexPhone.kt).
            notification: { channel_id: 'activity', icon: 'ic_notification', color: '#7C3AED' },
          },
        },
      }),
    },
  );
  if (response.ok) return true;
  const details = await response.text();
  // The app was uninstalled or the token expired: forget this phone.
  if (details.includes('UNREGISTERED') || details.includes('not a valid FCM registration token')) {
    await fetch(`https://firestore.googleapis.com/v1/${phone.name}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
  }
  return false;
}

async function listPhones(projectId, token) {
  const phones = [];
  let pageToken = '';
  do {
    const url = new URL(
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/pushTokens`,
    );
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!response.ok) {
      throw new Error(`Firestore ${response.status}: ${await response.text()}`);
    }
    const page = await response.json();
    for (const document of page.documents || []) {
      const fields = document.fields || {};
      if (!fields.token?.stringValue) continue;
      phones.push({
        name: document.name,
        token: fields.token.stringValue,
        uid: fields.uid?.stringValue || '',
      });
    }
    pageToken = page.nextPageToken || '';
  } while (pageToken);
  return phones;
}

/** Returns the user id of a valid Firebase ID token for [projectId]. */
async function verifyIdToken(idToken, projectId) {
  const [headerPart, payloadPart, signaturePart] = idToken.split('.');
  if (!signaturePart) throw new Error('Malformed token');
  const header = JSON.parse(new TextDecoder().decode(fromBase64Url(headerPart)));
  const payload = JSON.parse(new TextDecoder().decode(fromBase64Url(payloadPart)));
  const now = Math.floor(Date.now() / 1000);
  if (
    header.alg !== 'RS256' ||
    payload.aud !== projectId ||
    payload.iss !== `https://securetoken.google.com/${projectId}` ||
    typeof payload.sub !== 'string' ||
    !payload.sub ||
    payload.exp <= now ||
    payload.iat > now + 300
  ) {
    throw new Error('Invalid token claims');
  }
  const jwk = (await getGoogleKeys()).find((key) => key.kid === header.kid);
  if (!jwk) throw new Error('Unknown signing key');
  const key = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    fromBase64Url(signaturePart),
    new TextEncoder().encode(`${headerPart}.${payloadPart}`),
  );
  if (!valid) throw new Error('Bad signature');
  return payload.sub;
}

async function getGoogleKeys() {
  if (googleKeys.expiresAt > Date.now()) return googleKeys.keys;
  const response = await fetch(GOOGLE_KEYS_URL);
  if (!response.ok) throw new Error(`Google keys ${response.status}`);
  const data = await response.json();
  const maxAge = Number(/max-age=(\d+)/.exec(response.headers.get('Cache-Control') || '')?.[1] || 3600);
  googleKeys = { keys: data.keys || [], expiresAt: Date.now() + maxAge * 1000 };
  return googleKeys.keys;
}

/** OAuth access token for the service account, cached for about an hour. */
async function getAccessToken(account) {
  const now = Math.floor(Date.now() / 1000);
  if (accessToken.expiresAt > now + 60) return accessToken.token;
  const header = toBase64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = toBase64Url(
    JSON.stringify({
      iss: account.client_email,
      scope: SCOPES,
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claims}.${toBase64Url(signature)}`,
    }),
  });
  if (!response.ok) throw new Error(`OAuth ${response.status}: ${await response.text()}`);
  const data = await response.json();
  accessToken = { token: data.access_token, expiresAt: now + (data.expires_in || 3600) };
  return accessToken.token;
}

function pemToBytes(pem) {
  const base64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

function fromBase64Url(value) {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

function toBase64Url(value) {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : new Uint8Array(value);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function text(value, max) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

function reply(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
