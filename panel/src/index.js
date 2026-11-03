// vps-deploy-panel: stateless Worker that SSHes into a VPS (edgeport, cloudflare:sockets)
// and runs one of 3 whitelisted deploy scripts detached; poll/stream the log by job id.
// No password/key/link is ever logged or stored server-side. State the browser needs to resume
// is returned as an AES-GCM "ticket" (key = Worker secret TICKET_KEY, expires in 6h).
import { connect } from 'edgeport/ssh';
import PAGE from './page.html';

// Where the three scripts are downloaded from. Anyone deploying their own copy can point
// these at their own mirror with SETUP_URL / NEXUS_URL / HY2_URL, or move the whole set with
// SCRIPT_BASE. Defaults = the public repo on GitHub.
const DEFAULT_BASE = 'https://raw.githubusercontent.com/kottregrossmeyer-lab/one-click-vps-deploy/main';
const SCRIPTS = {
  setup: { path: '/subconverter/setup.sh', label: 'setup.sh', env: 'SETUP_URL' },
  hy2: { path: '/hy2-bundle/hy2.sh', label: 'hy2.sh', env: 'HY2_URL' },
};
const scriptUrl = (env, key) => env[SCRIPTS[key].env] || (env.SCRIPT_BASE || DEFAULT_BASE) + SCRIPTS[key].path;
const TICKET_TTL = 6 * 3600 * 1000;
// Public mode: no token needed, but every IP gets N job starts per UTC day (owner token = unlimited).
const isPublic = (env) => env.PUBLIC_MODE === '1';
const dayLimit = (env) => Number(env.DAILY_LIMIT) || 5;
const globalLimit = (env) => Number(env.GLOBAL_DAILY) || 300;
const dayKey = () => new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 10); // quota resets at 00:00 Beijing
const dec = (b) => (typeof b === 'string' ? b : new TextDecoder().decode(b || new Uint8Array()));
const enc = new TextEncoder();
const jsonL = (lang, o, st = 200) => new Response(JSON.stringify(o && o.error ? { ...o, error: tr(o.error, lang) } : o), { status: st, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
const shq = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;

const ZH = {
  'ticket expired': '凭证已过期（有效期 6 小时），请重新运行',
  'invalid ticket': '凭证无效',
  'invalid host (IPv4 or domain only)': '主机无效（仅支持 IPv4 或域名）',
  'private/reserved address not allowed': '不允许使用内网/保留地址',
  'internal hostname not allowed': '不允许使用内部主机名',
  'invalid port': '端口无效（1-65535）',
  'bad body': '请求格式错误',
  'port 25 is blocked': '端口 25 被屏蔽',
  'invalid user': '用户名无效',
  'password or private key required': '请填写密码或私钥',
  'password too long': '密码过长',
  'key must be a PKCS8 PEM (PRIVATE KEY header); convert OpenSSH keys with: ssh-keygen -p -m PKCS8 -f key': '私钥必须是 PKCS8 PEM 格式（以 PRIVATE KEY 头开始）；OpenSSH 格式可用 ssh-keygen -p -m PKCS8 -f 私钥文件 转换',
  'unknown script': '未知脚本',
  'node link must start with vless:// or hysteria2:// (no spaces)': '节点链接必须以 vless:// 或 hysteria2:// 开头（不能含空格）',
  'invalid public IP': '公网 IP 无效',
  'invalid answers': '预设回答无效（最多 60 行，每行不超过 300 字符，不含控制字符）',
  'setup.sh needs a node link (vless:// or hysteria2://)': 'setup.sh 需要填写节点链接（vless:// 或 hysteria2://）',
  'SSH connect/login timed out (20s) - check host, port, firewall, credentials': 'SSH 连接/登录超时（20 秒）——请检查主机、端口、防火墙和账号密码',
  'job not found on host (cleaned up?)': '在目标机器上找不到该任务（可能已被清理）',
  'POST only': '仅支持 POST',
  'server not configured': '服务端未配置',
  'rate limited': '请求过于频繁，请稍后再试',
  'forbidden': '访问令牌错误',
  'bad json': '请求不是合法的 JSON',
  'too many job starts, wait a minute': '启动任务过于频繁，请等待一分钟',
  'daily limit reached': '这个 IP 今天的免费次数用完了，明天再来，或者自己部署一份',
  'not found': '接口不存在',
  'human check failed': '人机验证没通过，请再点一次',
  'internal error': '内部错误',
};
function tr(m, lang) {
  if (lang !== 'zh') return m;
  if (ZH[m]) return ZH[m];
  let r;
  if ((r = /^SSH connect\/login failed: (.*)$/s.exec(m))) return 'SSH 连接/登录失败：' + r[1].replace('authentication failed', '认证失败（账号或密码/私钥错误）');
  if ((r = /^launch failed on remote \(exit (.*)\)$/.exec(m))) return '在目标机器上启动任务失败（退出码 ' + r[1] + '）';
  return m;
}
const T = (lang, zh, en) => (lang === 'zh' ? zh : en);
class UserError extends Error {}
const bad = (m) => { throw new UserError(m); };

// ---------- ticket crypto ----------
const b64u = (u8) => btoa(String.fromCharCode(...u8)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64u = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
async function tkey(env) {
  const raw = await crypto.subtle.digest('SHA-256', enc.encode('vps-deploy-panel/ticket/' + env.TICKET_KEY));
  return crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt', 'decrypt']);
}
async function seal(env, obj) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await tkey(env), enc.encode(JSON.stringify(obj))));
  const out = new Uint8Array(12 + ct.length); out.set(iv); out.set(ct, 12);
  return b64u(out);
}
async function open(env, ticket) {
  try {
    const raw = unb64u(String(ticket));
    const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: raw.slice(0, 12) }, await tkey(env), raw.slice(12));
    const o = JSON.parse(dec(new Uint8Array(pt)));
    if (!o.exp || Date.now() > o.exp) bad('ticket expired');
    return o;
  } catch (e) { if (e instanceof UserError) throw e; bad('invalid ticket'); }
}

// ---------- input validation ----------
const HOST_RE = /^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}|(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63})$/i;
function validHost(h) {
  if (typeof h !== 'string' || !HOST_RE.test(h)) bad('invalid host (IPv4 or domain only)');
  const m = /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/.exec(h);
  if (m) {
    const [a, b] = [+m[1], +m[2]];
    if (a === 0 || a === 10 || a === 127 || a >= 224 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127))
      bad('private/reserved address not allowed');
  } else if (/(^|\.)(localhost|local|internal|lan)$/i.test(h)) bad('internal hostname not allowed');
  return h;
}
const port = (v, d) => {
  if (v === undefined || v === null || v === '') return d;
  const n = Number(v); if (!Number.isInteger(n) || n < 1 || n > 65535) bad('invalid port');
  return n;
};
const USER_RE = /^[a-z_][a-z0-9_.-]{0,31}$/i;
const LINK_RE = /^(vless|hysteria2|hy2):\/\/[\x21-\x7e]{4,1900}$/;
function validateStart(b) {
  if (!b || typeof b !== 'object') bad('bad body');
  const o = {};
  o.host = validHost(b.host);
  o.port = port(b.port, 22); if (o.port === 25) bad('port 25 is blocked');
  o.user = b.user || 'root'; if (!USER_RE.test(o.user)) bad('invalid user');
  o.password = typeof b.password === 'string' ? b.password : '';
  o.key = typeof b.key === 'string' ? b.key.trim() : '';
  if (!o.password && !o.key) bad('password or private key required');
  if (o.password.length > 256) bad('password too long');
  if (o.key && (!/^-----BEGIN (?:PRIVATE|RSA PRIVATE|EC PRIVATE) KEY-----/.test(o.key) || o.key.length > 8000)) bad('key must be a PKCS8 PEM (PRIVATE KEY header); convert OpenSSH keys with: ssh-keygen -p -m PKCS8 -f key');
  o.script = b.script; if (!SCRIPTS[o.script]) bad('unknown script');
  o.dry = !!b.dry;
  const a = b.args || {};
  o.link = (a.link || '').trim(); o.link2 = (a.link2 || '').trim();
  for (const l of [o.link, o.link2]) if (l && !LINK_RE.test(l)) bad('node link must start with vless:// or hysteria2:// (no spaces)');
  o.publicIp = (a.publicIp || '').trim(); if (o.publicIp && !/^\d{1,3}(\.\d{1,3}){3}$/.test(o.publicIp)) bad('invalid public IP');
  o.httpsPort = a.httpsPort ? String(port(a.httpsPort)) : ''; o.httpPort = a.httpPort ? String(port(a.httpPort)) : '';
  o.answers = (Array.isArray(a.answers) ? a.answers : String(a.answers || '').split('\n')).map((x) => String(x).replace(/[\r\n\t]/g, ' '));
  if (o.answers.length > 60 || o.answers.some((x) => typeof x !== 'string' || x.length > 300 || /[\x00-\x08\x0b-\x1f\x7f]/.test(x))) bad('invalid answers');
  if (o.script === 'setup' && !o.dry && !o.link && !o.link2) bad('setup.sh needs a node link (vless:// or hysteria2://)');
  return o;
}

// ---------- ssh ----------
function sshOpts(o) {
  const x = { hostname: o.host, port: o.port, username: o.user };
  if (o.key) x.privateKey = { pem: o.key }; else x.password = o.password;
  return x;
}
async function sshConnect(o) {
  const t = new Promise((_, rej) => setTimeout(() => rej(new UserError('SSH connect/login timed out (20s) - check host, port, firewall, credentials')), 20000));
  try { return await Promise.race([connect(sshOpts(o)), t]); }
  catch (e) { if (e instanceof UserError) throw e; bad('SSH connect/login failed: ' + String(e && e.message || e).replace(/password[^,;]*/gi, '***').slice(0, 200)); }
}

// ---------- job script generation (fixed templates; user input only as quoted data) ----------
function buildPayload(env, id, o, lang) {
  const S = SCRIPTS[o.script], SRC = scriptUrl(env, o.script), D = `/tmp/dp-${id}`, EOB = `__EOB_${id}__`;
  const body = [];
  body.push(`rm -f "$0"`, `D=${D}`);
  body.push(`SUDO=""; if [ "$(id -u)" -ne 0 ]; then SUDO="sudo -n -E"; fi`);
  body.push(`echo ">> [panel] ${T(lang, '任务', 'job')} ${id}: ${S.label}${o.dry ? T(lang, '（试运行：仅下载并检查语法）', ' (DRY RUN: download + syntax check only)') : ''} @ $(hostname) / $(id -un)"`);
  body.push(`curl -fsSL --retry 2 --connect-timeout 20 --max-time 120 -o $D/script.sh ${shq(SRC)} || { echo "[panel] ${T(lang, '下载失败：', 'download failed: ')}${SRC}"; exit 1; }`);
  body.push(`echo ">> [panel] ${T(lang, '已下载', 'downloaded')} $(wc -c < $D/script.sh) bytes, md5 $(md5sum < $D/script.sh | cut -c1-12)"`);
  if (o.dry) {
    body.push(`bash -n $D/script.sh && echo ">> [panel] ${T(lang, '语法检查通过', 'syntax OK')}"`, `head -c 400 $D/script.sh | head -8`);
    body.push(`echo ">> [panel] ${T(lang, '脚本里的交互提问（源码顺序）：', 'interactive prompts found in the script:')}"`, `grep -nE 'read -[a-z]* ?"|box_input "' $D/script.sh | sed 's/^/   /' | head -40 || true`);
    if (o.script === 'hy2') body.push(`curl -fsSI --max-time 20 https://mirror.notebase.cn/bundle/hy2-bundle.tar.gz | head -4`);
    body.push(`echo ">> [panel] ${T(lang, '试运行结束，未执行任何脚本内容', 'dry run finished, nothing was executed')}"`);
  } else {
    let ans;
    if (o.script === 'setup') {
      if (o.link) body.push(`export SUB_LINK=${shq(o.link)}`);
      if (o.link2) body.push(`export SUB_LINK2=${shq(o.link2)}`);
      // prompts of deploy.sh: access mode (blank=public IP), public IP (blank=auto), HTTPS port, HTTP port
      // setup.sh re-prompts forever if its auto-detect fails, so hand it an explicit IP when we have one.
      const ipv4 = /^\d{1,3}(\.\d{1,3}){3}$/.test(o.host) && !/^(10\.|127\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(o.host);
      ans = ['', o.publicIp || (ipv4 ? o.host : ''), o.httpsPort, o.httpPort];
    } else ans = o.answers;
    body.push(`export TERM=xterm DEBIAN_FRONTEND=noninteractive`);
    body.push(`printf '%s\\n' ${ans.map(shq).join(' ')} | $SUDO bash $D/script.sh`);
  }
  const outer = [
    '#!/bin/bash',
    `rm -f "$0"`,
    `D=${D}`,
    `cat > $D/body.sh <<'${EOB}'`,
    body.join('\n'),
    EOB,
    `chmod 700 $D/body.sh`,
    `setsid bash $D/body.sh </dev/null &`,
    `BP=$!; echo $BP > $D/pid; wait $BP; echo $? > $D/exit`,
    '',
  ].join('\n');
  return outer;
}
const launchCmd = (id) => `D=/tmp/dp-${id}; umask 077; mkdir -m 700 $D && cat > $D/run.sh && chmod 700 $D/run.sh && : > $D/log && (setsid nohup bash $D/run.sh </dev/null >> $D/log 2>&1 &) ; echo launched`;

async function startJob(env, o, lang) {
  const id = [...crypto.getRandomValues(new Uint8Array(6))].map((x) => x.toString(16).padStart(2, '0')).join('');
  await using ssh = await sshConnect(o);
  await using ch = await ssh.execStream(launchCmd(id));
  await ch.write(buildPayload(env, id, o, lang));
  await ch.eof();
  const rd = ch.stdout.getReader(); let out = '';
  for (;;) { const { value, done } = await rd.read(); if (done) break; out += dec(value); }
  const ex = await ch.exit;
  if (!/launched/.test(out)) bad('launch failed on remote (exit ' + (ex && ex.code) + ')');
  const ticket = await seal(env, { h: o.host, po: o.port, u: o.user, pw: o.password, k: o.key, id, s: o.script, dry: o.dry, exp: Date.now() + TICKET_TTL });
  return { id, ticket, script: o.script, host: o.host, dry: o.dry, expires: Date.now() + TICKET_TTL };
}
const fromTicket = (t) => ({ host: t.h, port: t.po, user: t.u, password: t.pw, key: t.k });
const CHUNK = 200000;
async function status(t, off) {
  await using ssh = await sshConnect(fromTicket(t));
  const D = `/tmp/dp-${t.id}`;
  const ex = await ssh.exec(`cat ${D}/exit 2>/dev/null; [ -d ${D} ] && echo DIR || echo NODIR`); // exit BEFORE log read: no lost tail
  const e = dec(ex.stdout).trim().split('\n');
  if (e[e.length - 1] === 'NODIR') bad('job not found on host (cleaned up?)');
  const code = e.length > 1 && e[0] !== '' ? parseInt(e[0], 10) : null;
  const r = await ssh.exec(`tail -c +${off + 1} ${D}/log 2>/dev/null | head -c ${CHUNK}`);
  let bytes = r.stdout instanceof Uint8Array ? r.stdout : enc.encode(dec(r.stdout));
  let end = bytes.length;
  for (let i = end - 1, n = 0; i >= 0 && n < 4; i--, n++) { // do not cut a UTF-8 char in half
    const c = bytes[i];
    if ((c & 0xc0) === 0x80) continue; // continuation byte, keep looking back for the lead byte
    const need = c >= 0xf0 ? 4 : c >= 0xe0 ? 3 : c >= 0xc0 ? 2 : 1;
    if (end - i < need) end = i;
    break;
  }
  const text = new TextDecoder('utf-8').decode(bytes.slice(0, end)); // non-fatal: invalid bytes become U+FFFD
  return { text, next: off + end, done: code !== null && bytes.length < CHUNK, code };
}
async function cancel(t) {
  await using ssh = await sshConnect(fromTicket(t));
  const D = `/tmp/dp-${t.id}`;
  const r = await ssh.exec(`[ -f ${D}/pid ] && kill -TERM -- -$(cat ${D}/pid) 2>&1 && echo killed || echo nothing-to-kill`);
  return { result: dec(r.stdout).trim() };
}


async function turnstileOk(env, token, ip) {
  if (typeof token !== 'string' || token.length < 10 || token.length > 2048) return false;
  try {
    const r = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ secret: env.TURNSTILE_SECRET, response: token, remoteip: ip }),
    });
    const j = await r.json();
    return !!j.success;
  } catch { return false; }
}

// ---------- daily quota (public mode) ----------
async function quota(env, ip, consume) {
  if (!env.QUOTA) return { ok: true, left: null };
  const stub = env.QUOTA.get(env.QUOTA.idFromName('v1'));
  const r = await stub.fetch('https://quota.internal/', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ day: dayKey(), ip, limit: dayLimit(env), global: globalLimit(env), consume }) });
  return r.json();
}

// ---------- rate limit / auth ----------
async function limited(env, name, key) {
  const b = env[name]; if (!b) return false;
  try { const { success } = await b.limit({ key }); return !success; } catch { return false; }
}
const ctEq = (a, b) => { if (a.length !== b.length) return false; let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i); return r === 0; };

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url), p = url.pathname;
    const ip = req.headers.get('cf-connecting-ip') || 'x';
    const LANG = req.headers.get('x-lang') === 'zh' ? 'zh' : 'en';
    const json = (o, st = 200) => jsonL(LANG, o, st);
    if (req.method === 'GET' && p === '/') {
      const sitekey = String(env.TURNSTILE_SITEKEY || '').replace(/[^0-9A-Za-z_-]/g, '');
      const html = PAGE.replace('__TURNSTILE_SITEKEY__', sitekey);
      return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'x-frame-options': 'DENY', 'referrer-policy': 'no-referrer' } });
    }
    if (!p.startsWith('/api/')) return new Response('not found', { status: 404 });
    if (await limited(env, 'RL_API', 'api:' + ip)) return json({ error: 'rate limited' }, 429);
    const tok = req.headers.get('x-token') || '';
    const owner = !!env.PANEL_TOKEN && ctEq(tok, env.PANEL_TOKEN);
    if (p === '/api/info') {
      if (!env.TICKET_KEY) return json({ error: 'server not configured' }, 500);
      let left = null;
      if (isPublic(env) && !owner) { try { left = (await quota(env, ip, false)).left; } catch { left = null; } }
      return json({ public: isPublic(env), owner, daily: dayLimit(env), left });
    }
    if (req.method !== 'POST') return json({ error: 'POST only' }, 405);
    if (!env.TICKET_KEY || (!isPublic(env) && !env.PANEL_TOKEN)) return json({ error: 'server not configured' }, 500);
    if (!owner) {
      if (!isPublic(env)) {
        if (await limited(env, 'RL_AUTH', 'auth:' + ip)) return json({ error: 'rate limited' }, 429);
        return json({ error: 'forbidden' }, 403);
      }
      if (await limited(env, 'RL_AUTH', 'auth:' + ip)) return json({ error: 'rate limited' }, 429);
    }
    let body; try { body = await req.json(); } catch { return json({ error: 'bad json' }, 400); }
    try {
      if (p === '/api/start') {
        if (await limited(env, 'RL_START', 'start:' + ip)) return json({ error: 'too many job starts, wait a minute' }, 429);
        const o = validateStart(body);
        // 公开使用要过人机验证。部署者令牌不加这一道。没配密钥的自建副本保持原样。
        if (!owner && env.TURNSTILE_SECRET && !(await turnstileOk(env, body.turnstile, ip))) return json({ error: 'human check failed' }, 403);
        if (!owner) {
          let q = { ok: true, left: null };
          try { q = await quota(env, ip, true); } catch (e) { /* DO hiccup must not lock everyone out */ }
          if (!q.ok) return json({ error: 'daily limit reached' }, 429);
        }
        return json(await startJob(env, o, LANG));
      }
      const t = await open(env, body.ticket);
      if (p === '/api/status') return json(await status(t, Math.max(0, parseInt(body.off || 0, 10) || 0)));
      if (p === '/api/cancel') return json(await cancel(t));
      if (p === '/api/stream') {
        const off = Math.max(0, parseInt(body.off || 0, 10) || 0);
        const { readable, writable } = new TransformStream(); const w = writable.getWriter();
        ctx.waitUntil((async () => {
          const t0 = Date.now(), D = `/tmp/dp-${t.id}`, lang = LANG;
          try {
            await using ssh = await sshConnect(fromTicket(t));
            await using ch = await ssh.execStream(`tail -c +${off + 1} -F ${D}/log 2>/dev/null & T=$!; while [ ! -f ${D}/exit ]; do sleep 1; done; sleep 1.5; kill $T 2>/dev/null; echo; echo "${T(lang, '[panel] 任务结束，退出码', '[panel] job finished, exit=')}$(cat ${D}/exit)"`);
            const rd = ch.stdout.getReader();
            for (;;) { const { value, done } = await rd.read(); if (done) break; await w.write(value); }
          } catch (e) { await w.write(enc.encode(T(lang, '\n[panel] 实时流出错：', '\n[panel] stream error: ') + (e && e.message || e) + '\n')); }
          finally { await w.close().catch(() => {}); }
        })());
        return new Response(readable, { headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' } });
      }
      return json({ error: 'not found' }, 404);
    } catch (e) {
      if (e instanceof UserError) return json({ error: e.message }, 400);
      return json({ error: 'internal error' }, 500); // never echo internals (could contain request data)
    }
  },
};

// Durable Object: one counter namespace, keyed by day + IP, plus a global day counter.
export class Quota {
  constructor(state) { this.state = state; }
  async fetch(req) {
    const { day, ip, limit, global, consume } = await req.json();
    const lastDay = await this.state.storage.get('day');
    if (lastDay !== day) {
      const all = await this.state.storage.list();
      const stale = [...all.keys()].filter((k) => k.startsWith('u:') && !k.startsWith('u:' + day + ':'));
      if (stale.length) await this.state.storage.delete(stale);
      await this.state.storage.put('day', day);
    }
    const uk = `u:${day}:${ip}`, gk = `g:${day}`;
    const cur = await this.state.storage.get([uk, gk]);
    let n = cur.get(uk) || 0, g = cur.get(gk) || 0;
    const ok = n < limit && g < global;
    if (consume && ok) { n++; g++; await this.state.storage.put({ [uk]: n, [gk]: g }); }
    return Response.json({ ok, n, g, left: Math.max(0, limit - n) });
  }
}
