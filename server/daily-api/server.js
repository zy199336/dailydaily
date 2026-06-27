require('dotenv').config();

const fastify = require('fastify')({ logger: true });
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');
globalThis.WebSocket = require('ws');
const { createClient } = require('@supabase/supabase-js');

const wechatAppId = process.env.WECHAT_APP_ID;
const wechatAppSecret = process.env.WECHAT_APP_SECRET;
const tokenSecret = process.env.API_TOKEN_SECRET || 'dev-only-change-me';
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_KEY;
const scheduleTable = 'daily_schedule_tasks';
const accountLinksFile = path.join(__dirname, 'data', 'account_links.json');
const supabase =
  supabaseUrl && supabaseKey ? createClient(supabaseUrl, supabaseKey) : null;

fastify.get('/health', async () => ({
  ok: true,
  service: 'daily-api',
  time: new Date().toISOString(),
}));

fastify.get('/', async () => ({
  ok: true,
  message: 'daily-api is running',
}));

fastify.post('/auth/wechat-login', async (request, reply) => {
  const code = request.body?.code;
  if (!code || typeof code !== 'string') {
    return reply.code(400).send({ ok: false, error: 'missing_code' });
  }
  if (!wechatAppId || !wechatAppSecret) {
    return reply.code(500).send({ ok: false, error: 'wechat_not_configured' });
  }

  const url = new URL('https://api.weixin.qq.com/sns/jscode2session');
  url.searchParams.set('appid', wechatAppId);
  url.searchParams.set('secret', wechatAppSecret);
  url.searchParams.set('js_code', code);
  url.searchParams.set('grant_type', 'authorization_code');

  const response = await fetch(url);
  const payload = await response.json();

  if (!response.ok || payload.errcode) {
    request.log.warn({ payload }, 'wechat code2session failed');
    return reply.code(401).send({
      ok: false,
      error: 'wechat_login_failed',
      errcode: payload.errcode,
      errmsg: payload.errmsg,
    });
  }

  const linkedAccount = await linkedAccountForOpenid(payload.openid);
  return {
    ok: true,
    openid: payload.openid,
    unionid: payload.unionid ?? null,
    linked: Boolean(linkedAccount),
    email: linkedAccount?.email ?? null,
    token: signToken({
      openid: payload.openid,
      userId: linkedAccount?.userId ?? null,
      email: linkedAccount?.email ?? null,
    }),
  };
});

fastify.post('/auth/link-email', async (request, reply) => {
  if (!supabase || !supabaseUrl || !supabaseKey) {
    return reply.code(500).send({ ok: false, error: 'supabase_not_configured' });
  }

  const authorization = request.headers.authorization || '';
  const token = authorization.startsWith('Bearer ')
    ? authorization.slice('Bearer '.length)
    : '';
  const wechatAuth = verifyWechatToken(token);
  if (!wechatAuth?.openid) {
    return reply.code(401).send({ ok: false, error: 'wechat_login_required' });
  }

  const email = String(request.body?.email || '').trim();
  const password = String(request.body?.password || '');
  if (!email || !password) {
    return reply.code(400).send({ ok: false, error: 'missing_email_password' });
  }

  const authClient = createClient(supabaseUrl, supabaseKey);
  const { data, error } = await authClient.auth.signInWithPassword({
    email,
    password,
  });
  const user = data?.user;
  if (error || !user) {
    request.log.warn({ error }, 'email link sign-in failed');
    return reply.code(401).send({ ok: false, error: 'invalid_email_password' });
  }

  const link = {
    userId: user.id,
    email: user.email || email,
    linkedAt: new Date().toISOString(),
  };
  await saveLinkedAccount(wechatAuth.openid, link);

  return {
    ok: true,
    linked: true,
    openid: wechatAuth.openid,
    email: link.email,
    token: signToken({
      openid: wechatAuth.openid,
      userId: link.userId,
      email: link.email,
    }),
  };
});

fastify.post('/auth/register-link-email', async (request, reply) => {
  if (!supabase || !supabaseUrl || !supabaseKey) {
    return reply.code(500).send({ ok: false, error: 'supabase_not_configured' });
  }

  const authorization = request.headers.authorization || '';
  const token = authorization.startsWith('Bearer ')
    ? authorization.slice('Bearer '.length)
    : '';
  const wechatAuth = verifyWechatToken(token);
  if (!wechatAuth?.openid) {
    return reply.code(401).send({ ok: false, error: 'wechat_login_required' });
  }

  const email = String(request.body?.email || '').trim();
  const password = String(request.body?.password || '');
  if (!email || !password) {
    return reply.code(400).send({ ok: false, error: 'missing_email_password' });
  }

  const authClient = createClient(supabaseUrl, supabaseKey);
  const { data, error } = await authClient.auth.signUp({
    email,
    password,
  });
  const user = data?.user;
  if (error || !user) {
    request.log.warn({ error }, 'email register link failed');
    return reply.code(400).send({ ok: false, error: 'register_failed' });
  }

  const link = {
    userId: user.id,
    email: user.email || email,
    linkedAt: new Date().toISOString(),
  };
  await saveLinkedAccount(wechatAuth.openid, link);

  return {
    ok: true,
    linked: true,
    openid: wechatAuth.openid,
    email: link.email,
    token: signToken({
      openid: wechatAuth.openid,
      userId: link.userId,
      email: link.email,
    }),
  };
});

fastify.get('/tasks', async (request, reply) => {
  const auth = await authenticate(request, reply);
  if (!auth || !supabase) return;

  let query = supabase
    .from(scheduleTable)
    .select('*')
    .is('deleted_at', null)
    .order('start_date', { ascending: true })
    .order('priority', { ascending: true });
  query = applyOwnerFilter(query, auth);
  const { data, error } = await query;

  if (error) {
    request.log.error({ error }, 'failed to list tasks');
    return reply.code(500).send({ ok: false, error: 'task_list_failed' });
  }
  return { ok: true, account: accountForAuth(auth), tasks: data ?? [] };
});

fastify.post('/tasks', async (request, reply) => {
  const auth = await authenticate(request, reply);
  if (!auth || !supabase) return;

  const task = normalizeTask(request.body?.task, auth);
  if (!task) {
    return reply.code(400).send({ ok: false, error: 'invalid_task' });
  }

  const { data, error } = await supabase
    .from(scheduleTable)
    .upsert(task)
    .select()
    .single();

  if (error) {
    request.log.error({ error }, 'failed to upsert task');
    return reply.code(500).send({ ok: false, error: 'task_save_failed' });
  }
  return { ok: true, task: data };
});

fastify.patch('/tasks/:id', async (request, reply) => {
  const auth = await authenticate(request, reply);
  if (!auth || !supabase) return;

  const task = normalizeTask(
    { ...request.body?.task, id: request.params.id },
    auth,
  );
  if (!task) {
    return reply.code(400).send({ ok: false, error: 'invalid_task' });
  }

  const { data, error } = await supabase
    .from(scheduleTable)
    .upsert(task)
    .select()
    .single();

  if (error) {
    request.log.error({ error }, 'failed to update task');
    return reply.code(500).send({ ok: false, error: 'task_update_failed' });
  }
  return { ok: true, task: data };
});

fastify.delete('/tasks/:id', async (request, reply) => {
  const auth = await authenticate(request, reply);
  if (!auth || !supabase) return;

  const taskId = String(request.params.id || '').trim();
  if (!isUuid(taskId)) {
    return { ok: true };
  }

  const now = new Date().toISOString();
  let query = supabase
    .from(scheduleTable)
    .update({ deleted_at: now, updated_at: now })
    .eq('id', taskId);
  query = applyOwnerFilter(query, auth);
  const { error } = await query;

  if (error) {
    request.log.error({ error }, 'failed to delete task');
    return reply.code(500).send({ ok: false, error: 'task_delete_failed' });
  }
  return { ok: true };
});

fastify.post('/sync', async (request, reply) => {
  const auth = await authenticate(request, reply);
  if (!auth || !supabase) return;

  const incoming = Array.isArray(request.body?.tasks) ? request.body.tasks : [];
  const normalized = incoming
    .map((task) => normalizeTask(task, auth))
    .filter(Boolean);

  if (normalized.length > 0) {
    const { error } = await supabase.from(scheduleTable).upsert(normalized);
    if (error) {
      request.log.error({ error }, 'failed to sync tasks');
      return reply.code(500).send({ ok: false, error: 'task_sync_failed' });
    }
  }

  let query = supabase
    .from(scheduleTable)
    .select('*')
    .order('start_date', { ascending: true })
    .order('priority', { ascending: true });
  query = applyOwnerFilter(query, auth);
  const { data, error } = await query;

  if (error) {
    request.log.error({ error }, 'failed to load synced tasks');
    return reply.code(500).send({ ok: false, error: 'task_load_failed' });
  }
  return { ok: true, account: accountForAuth(auth), tasks: data ?? [] };
});

const port = Number(process.env.PORT || 3000);

fastify.listen({ port, host: '127.0.0.1' }).catch((error) => {
  fastify.log.error(error);
  process.exit(1);
});

function ownerIdForOpenid(openid) {
  return `wechat:${openid}`;
}

function signToken(payload) {
  const body = base64UrlEncode(
    JSON.stringify({ ...payload, iat: Math.floor(Date.now() / 1000) }),
  );
  const signature = crypto
    .createHmac('sha256', tokenSecret)
    .update(body)
    .digest('base64url');
  return `${body}.${signature}`;
}

function verifyWechatToken(token) {
  const [body, signature] = String(token || '').split('.');
  if (!body || !signature) return null;
  const expected = crypto
    .createHmac('sha256', tokenSecret)
    .update(body)
    .digest('base64url');
  const actualBuffer = Buffer.from(signature);
  const expectedBuffer = Buffer.from(expected);
  if (
    actualBuffer.length !== expectedBuffer.length ||
    !crypto.timingSafeEqual(actualBuffer, expectedBuffer)
  ) {
    return null;
  }
  try {
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
    if (!payload.openid) return null;
    return {
      kind: 'wechat',
      openid: payload.openid,
      ownerId: payload.userId
        ? `supabase:${payload.userId}`
        : ownerIdForOpenid(payload.openid),
      userId: payload.userId ?? null,
      email: payload.email ?? null,
      deviceId: 'wechat-miniapp',
    };
  } catch {
    return null;
  }
}

async function authenticate(request, reply) {
  if (!supabase) {
    reply.code(500).send({ ok: false, error: 'supabase_not_configured' });
    return null;
  }
  const authorization = request.headers.authorization || '';
  const token = authorization.startsWith('Bearer ')
    ? authorization.slice('Bearer '.length)
    : '';

  const wechatPayload = verifyWechatToken(token);
  if (wechatPayload) {
    const linkedAccount = wechatPayload.userId
      ? { userId: wechatPayload.userId, email: wechatPayload.email }
      : await linkedAccountForOpenid(wechatPayload.openid);
    if (linkedAccount?.userId) {
      return {
        kind: 'supabase',
        openid: wechatPayload.openid,
        ownerId: `supabase:${linkedAccount.userId}`,
        userId: linkedAccount.userId,
        email: linkedAccount.email ?? null,
        deviceId: 'wechat-miniapp',
      };
    }
    return wechatPayload;
  }

  const { data, error } = await supabase.auth.getUser(token);
  const user = data?.user;
  if (error || !user) {
    reply.code(401).send({ ok: false, error: 'unauthorized' });
    return null;
  }
  return {
    kind: 'supabase',
    openid: null,
    ownerId: `supabase:${user.id}`,
    userId: user.id,
    deviceId: 'flutter-app',
  };
}

function applyOwnerFilter(query, auth) {
  if (auth.kind === 'supabase') {
    return query.eq('user_id', auth.userId);
  }
  return query.eq('owner_id', auth.ownerId);
}

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
    String(value || '').trim(),
  );
}

function normalizeTask(task, auth) {
  if (!task || typeof task !== 'object') return null;
  const now = new Date().toISOString();
  const incomingId = String(task.id || '').trim();
  const id = isUuid(incomingId) ? incomingId : crypto.randomUUID();
  const title = String(task.title || '').trim();
  const startDate = task.start_date || task.startDate;
  const endDate = task.end_date || task.endDate || startDate;
  if (!title || !startDate || !endDate) return null;

  return {
    id,
    title,
    description: task.description || null,
    start_date: startDate,
    end_date: endDate,
    start_time: task.start_time || task.startTime || null,
    end_time: task.end_time || task.endTime || null,
    is_all_day: task.is_all_day ?? task.isAllDay ?? true,
    is_completed: task.is_completed ?? task.isCompleted ?? false,
    owner_id: auth.kind === 'supabase'
      ? task.owner_id || task.ownerId || auth.ownerId
      : auth.ownerId,
    user_id: auth.kind === 'supabase' ? auth.userId : null,
    recurrence_rule: task.recurrence_rule || task.recurrenceRule || 'none',
    priority: Number(task.priority || 0),
    device_id: task.device_id || task.deviceId || auth.deviceId,
    created_at: task.created_at || task.createdAt || now,
    updated_at: now,
    deleted_at: task.deleted_at || task.deletedAt || null,
  };
}

function accountForAuth(auth) {
  return {
    linked: auth.kind === 'supabase' && Boolean(auth.openid),
    email: auth.email ?? null,
    kind: auth.kind,
  };
}

function base64UrlEncode(value) {
  return Buffer.from(value).toString('base64url');
}

async function readAccountLinks() {
  try {
    const raw = await fs.readFile(accountLinksFile, 'utf8');
    return JSON.parse(raw);
  } catch (error) {
    if (error.code === 'ENOENT') return {};
    throw error;
  }
}

async function linkedAccountForOpenid(openid) {
  if (!openid) return null;
  const links = await readAccountLinks();
  const link = links[openid];
  return link?.userId ? link : null;
}

async function saveLinkedAccount(openid, link) {
  const links = await readAccountLinks();
  links[openid] = link;
  await fs.mkdir(path.dirname(accountLinksFile), { recursive: true });
  await fs.writeFile(accountLinksFile, JSON.stringify(links, null, 2));
}
