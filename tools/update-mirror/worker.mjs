// Public release gateway for one repository. No credentials or arbitrary URLs.
import { APPROVED_RELEASES, CACHE_NAMESPACE, approvedTag, approvedMetadata } from './distribution.mjs';
export const REPOSITORY = 'mikufoxxx/Wenku8_Flutter';
const API = `https://api.github.com/repos/${REPOSITORY}/releases/`;
const MAX_ASSET = 300 * 1024 * 1024;
const VERSION = /^v?(\d+\.\d+\.\d+)(?:\+\d+)?$/;
const REDIRECT_HOSTS = new Set([
  'github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com',
]);
const BASE_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Expose-Headers': 'Content-Length, Content-Range, ETag, X-Wenku-Cache',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
};

function error(message, status = 502, details = {}) {
  return new Response(JSON.stringify({ error: message, ...details }), {
    status,
    headers: { ...BASE_HEADERS, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

class RegistryFailure extends Error {
  constructor(stage, status) {
    super(stage === 'http' ? `GitHub HTTP ${status}` : 'Registry refresh failed');
    this.stage = stage;
  }
}

async function registryStep(stage, action) {
  try { return await action(); }
  catch { throw new RegistryFailure(stage); }
}

function registryError(message, status, stage) {
  return error(message, status, { stage, policyNamespace: CACHE_NAMESPACE });
}

function output(response, method, state) {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(BASE_HEADERS)) headers.set(key, value);
  headers.set('X-Wenku-Cache', state);
  return new Response(method === 'HEAD' ? null : response.body, {
    status: response.status, headers,
  });
}

export async function release(suffix, origin, dependencies) {
  const { cache, fetcher, waitUntil } = dependencies;
  const policy = dependencies.approvedReleases ?? APPROVED_RELEASES;
  if (Object.keys(policy).length === 0 || (suffix !== 'latest' && !approvedTag(suffix.slice(5), policy))) {
    return { response: error('No published release', 404), state: 'MISS' };
  }
  const key = new Request(`${origin}/_release-cache-${CACHE_NAMESPACE}/${suffix}`);
  const hit = await cache.match(key);
  if (hit) {
    const cached = await hit.clone().json();
    const allowed = approvedMetadata(cached, policy);
    if (allowed && allowed.assets.length === cached.assets.length) return { response: hit, state: 'HIT' };
  }
  const upstream = dependencies.registry ? await dependencies.registry(suffix, dependencies.allowStale === true) : await fetchHeaders(fetcher, `${API}${suffix}`, {
    headers: {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'Wenku8-Release-Mirror',
      'X-GitHub-Api-Version': '2022-11-28',
    },
    redirect: 'manual',
  });
  if (upstream.status !== 200) {
    if (dependencies.registry) return { response: upstream, state: 'MISS' };
    await upstream.body?.cancel();
    return { response: error('GitHub release is temporarily unavailable', upstream.status === 404 ? 404 : 503), state: 'MISS' };
  }
  const reader = upstream.body.getReader();
  const chunks = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.length;
    if (length > 1024 * 1024) {
      await reader.cancel();
      throw new Error('Release metadata too large');
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  const metadata = approvedMetadata(JSON.parse(new TextDecoder().decode(bytes)), policy);
  if (!metadata) {
    return { response: error('No stable release', 404), state: 'MISS' };
  }
  const response = new Response(JSON.stringify(metadata), {
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': `public, max-age=0, s-maxage=${suffix === 'latest' ? 120 : 300}`, 'X-Wenku-Upstream': 'GitHub' },
  });
  const stale = upstream.headers.get('X-Wenku-Stale') === '1';
  if (!stale) waitUntil(cache.put(key, response.clone()).catch(() => {}));
  return { response, state: stale ? 'STALE' : 'MISS' };
}

async function fetchHeaders(fetcher, url, options) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try { return await fetcher(url, { ...options, signal: controller.signal }); }
  finally { clearTimeout(timer); }
}

async function assetResponse(request, url, match, dependencies) {
  const tag = decodeURIComponent(match[1]);
  const name = decodeURIComponent(match[2]);
  const version = VERSION.exec(tag)?.[1];
  if (!version || (!new Set([
    `wenku8-${version}-arm64-v8a.apk`, `wenku8-${version}-armeabi-v7a.apk`,
    `wenku8-${version}-x86_64.apk`, `wenku8-${version}-universal.apk`,
    `wenku8-${version}-source.zip`,
    `wenku8-${version}-ios-unsigned.ipa`, `wenku8-${version}-harmony-unsigned.hap`,
  ]).has(name) && !new RegExp('^Wenku8-' + version.replaceAll('.', '\\.') + '-[0-9]+-(ios-unsigned(?:-fixed)?\\.ipa|harmony-unsigned\\.hap)$').test(name))) return error('Unknown release asset', 404);
  const policy = dependencies.approvedReleases ?? APPROVED_RELEASES;
  // Apply approval before cached bytes, range requests and known attachment IDs.
  if (!approvedTag(tag, policy)) return error('Release unavailable', 410);
  if ([...url.searchParams.keys()].some(key => key !== 'asset') ||
      url.searchParams.getAll('asset').length > 1 ||
      (url.searchParams.has('asset') && !/^\d+$/.test(url.searchParams.get('asset')))) {
    return error('Invalid asset identity', 400);
  }
  if (url.searchParams.has('asset')) {
    if (!policy[tag].includes(Number(url.searchParams.get('asset')))) return error('Check for updates again', 409);
    const knownKey = `${url.origin}/${REPOSITORY}/releases/download/${encodeURIComponent(tag)}/${name}?asset=${url.searchParams.get('asset')}`;
    const headers = new Headers();
    if (request.headers.has('Range')) headers.set('Range', request.headers.get('Range'));
    if (!request.headers.has('If-Range')) {
      const verified = await dependencies.cache.match(new Request(knownKey, { headers }));
      if (verified) return output(verified, request.method, 'HIT');
    }
  }
  // Most downloads are the current release. Reuse the already requested latest
  // manifest instead of spending a second GitHub API call on the same release.
  const downloadDependencies = { ...dependencies, allowStale: true };
  let metadata = await release('latest', url.origin, downloadDependencies);
  if (metadata.response.status !== 200 || (await metadata.response.clone().json()).tag_name !== tag) {
    metadata = await release(`tags/${encodeURIComponent(tag)}`, url.origin, downloadDependencies);
  }
  if (metadata.response.status !== 200) return metadata.response;
  const data = await metadata.response.json();
  const expectedPath = `/${REPOSITORY}/releases/download/${tag}/${name}`;
  const asset = data.assets?.find(candidate => candidate.name === name &&
    Number.isSafeInteger(candidate.id) && candidate.id > 0 &&
    Number.isSafeInteger(candidate.size) && candidate.size > 0 && candidate.size <= MAX_ASSET &&
    candidate.browser_download_url && (() => {
      const source = new URL(candidate.browser_download_url);
      return source.protocol === 'https:' && source.hostname === 'github.com' &&
        !source.username && !source.password && !source.port && !source.search && !source.hash &&
        decodeURIComponent(source.pathname) === expectedPath;
    })());
  if (!asset || data.tag_name !== tag) return error('Unknown release asset', 404);
  if (url.searchParams.has('asset') && url.searchParams.get('asset') !== String(asset.id)) {
    return error('Release asset changed; check for updates again', 409);
  }
  const canonical = `${url.origin}/${REPOSITORY}/releases/download/${encodeURIComponent(tag)}/${name}?asset=${asset.id}`;
  const lookupHeaders = new Headers();
  const forwardHeaders = new Headers({ 'User-Agent': 'Wenku8-Release-Mirror', 'Accept-Encoding': 'identity' });
  for (const key of ['Range', 'If-Range']) {
    if (request.headers.has(key)) forwardHeaders.set(key, request.headers.get(key));
  }
  if (request.headers.has('Range')) lookupHeaders.set('Range', request.headers.get('Range'));
  if (!request.headers.has('If-Range')) {
    const hit = await dependencies.cache.match(new Request(canonical, { headers: lookupHeaders }));
    if (hit) return output(hit, request.method, 'HIT');
  }
  let upstreamURL = new URL(asset.browser_download_url);
  let upstream;
  for (let hop = 0; hop < 6; hop++) {
    if (upstreamURL.protocol !== 'https:' || upstreamURL.username || upstreamURL.password ||
        (upstreamURL.port && upstreamURL.port !== '443') || !REDIRECT_HOSTS.has(upstreamURL.hostname)) {
      return error('Invalid GitHub asset redirect');
    }
    upstream = await fetchHeaders(dependencies.fetcher, upstreamURL, { method: request.method, headers: forwardHeaders, redirect: 'manual' });
    if (![301, 302, 303, 307, 308].includes(upstream.status)) break;
    const location = upstream.headers.get('Location');
    await upstream.body?.cancel();
    if (!location) return error('Missing GitHub asset redirect');
    upstreamURL = new URL(location, upstreamURL);
  }
  if (![200, 206, 416].includes(upstream.status)) {
    await upstream.body?.cancel();
    return error(`GitHub download is temporarily unavailable (HTTP ${upstream.status})`, 503);
  }
  const headers = new Headers();
  for (const key of ['Content-Length', 'Content-Range', 'ETag', 'Last-Modified', 'Accept-Ranges']) {
    if (upstream.headers.has(key)) headers.set(key, upstream.headers.get(key));
  }
  if (upstream.status === 200 && Number(headers.get('Content-Length')) !== asset.size) {
    await upstream.body?.cancel();
    return error('GitHub asset size does not match its release');
  }
  headers.set('Content-Type', name.endsWith('.apk') ? 'application/vnd.android.package-archive' : 'application/zip');
  headers.set('Content-Disposition', `attachment; filename="${name}"`);
  headers.set('Cache-Control', upstream.status === 416 ? 'no-store' : 'public, max-age=0, s-maxage=3600');
  const response = new Response(upstream.body, { status: upstream.status, headers });
  if (request.method === 'GET' && upstream.status === 200 && !request.headers.has('Range')) {
    dependencies.waitUntil(dependencies.cache.put(new Request(canonical), response.clone()).catch(() => {}));
  }
  return output(response, request.method, 'MISS');
}

export async function handle(request, dependencies) {
  const url = new URL(request.url);
  if (!['GET', 'HEAD'].includes(request.method)) return error('Only GET and HEAD are supported', 405);
  try {
    if (url.pathname === '/' && !url.search) {
      return new Response(request.method === 'HEAD' ? null : HOME, { headers: {
        ...BASE_HEADERS, 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=300',
        'Content-Security-Policy': "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self' https://api.github.com; base-uri 'none'; frame-ancestors 'none'",
      } });
    }
    if (url.pathname === '/health' && !url.search) {
      return new Response(request.method === 'HEAD' ? null : JSON.stringify({ status: 'ok', repository: REPOSITORY, colo: request.cf?.colo ?? null, country: request.cf?.country ?? null, priority: 'updates' }), {
        headers: { ...BASE_HEADERS, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
      });
    }
    if (url.pathname === '/api/releases/latest' && !url.search) {
      const result = await release('latest', url.origin, dependencies);
      const response = output(result.response, request.method, result.state);
      // The internal shared manifest still caches for 120 seconds. Do not let
      // a browser retain the previous release across a withdrawal or rollback.
      response.headers.set('Cache-Control', 'no-store');
      return response;
    }
    if (/^\/api\/releases\/(ios|harmony)$/.test(url.pathname) && !url.search) {
      const extension = url.pathname.endsWith('/ios') ? '.ipa' : '.hap';
      const policy = dependencies.approvedReleases ?? APPROVED_RELEASES;
      const tags = Object.keys(policy).filter(tag => approvedTag(tag, policy))
        .sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
      for (const tag of tags) {
        const result = await release(`tags/${tag}`, url.origin, dependencies);
        if (result.response.status === 404) continue;
        if (result.response.status !== 200) return output(result.response, request.method, result.state);
        const data = await result.response.clone().json();
        const version = VERSION.exec(tag)?.[1];
        if (!data.assets.some(asset => asset.name.startsWith(`wenku8-${version}-`) && asset.name.endsWith(extension))) continue;
        const response = output(result.response, request.method, result.state);
        response.headers.set('Cache-Control', 'no-store');
        return response;
      }
      return error('No published release for this platform', 404);
    }
    const match = url.pathname.match(/^\/mikufoxxx\/Wenku8_Flutter\/releases\/download\/([^/]+)\/([^/]+)$/);
    if (match) return await assetResponse(request, url, match, dependencies);
    return error('This gateway serves Wenku8 releases only', 404);
  } catch {
    return error('Update service is temporarily unavailable');
  }
}

export default {
  async fetch(request, env, ctx) {
    const limiter = new URL(request.url).pathname.includes('/releases/download/')
      ? env.DOWNLOAD_LIMITER : env.READ_LIMITER;
    // Cloudflare sets this header at the edge. It is not a client-chosen key.
    // Generous burst limits accommodate shared mobile/NAT addresses.
    if (!limiter) return error('Rate limiter is not configured', 503);
    const { success } = await limiter.limit({ key: request.headers.get('CF-Connecting-IP') || 'unknown' });
    if (!success) {
      const response = error('Too many requests; retry in one minute', 429);
      response.headers.set('Retry-After', '60');
      return response;
    }
    return handle(request, { fetcher: (...args) => fetch(...args), cache: caches.default, waitUntil: task => ctx.waitUntil(task),
      registry: env.RELEASE_REGISTRY ? (suffix, stale) => env.RELEASE_REGISTRY.get(env.RELEASE_REGISTRY.idFromName(`public-releases:${CACHE_NAMESPACE}`)).fetch(`https://registry/${suffix}${stale ? '?download=1' : ''}`) : null });
  },
};

// One shared refresh per 120 s instead of a separate GitHub API budget per POP.
// The free SQLite object stores public release manifests, never visitor/account data.
export class ReleaseRegistry {
  constructor(ctx, env = {}, policy) { this.storage = ctx.storage; this.env = env; this.policyOverride = policy; this.pending = new Map(); this.cooldown = 0; }
  // The signed-asset approval belongs to deployed code, not a long-lived
  // object's constructor snapshot. An explicit test policy stays isolated.
  get activePolicy() { return this.policyOverride ?? APPROVED_RELEASES; }
  async fetch(request) {
    const url = new URL(request.url), suffix = url.pathname.slice(1);
    if (suffix !== 'latest' && !/^tags\/v?\d+\.\d+\.\d+(?:\+\d+)?$/.test(suffix) || suffix.length > 80) return error('Unknown release', 404);
    if (Object.keys(this.activePolicy).length === 0 || (suffix.startsWith('tags/') && !approvedTag(suffix.slice(5), this.activePolicy))) return registryError('No published release', 404, 'approval');
    const now = Date.now(), key = `release:${CACHE_NAMESPACE}:${suffix}`;
    let saved;
    try { saved = await this.storage.get(key); }
    catch { return registryError('Update service is temporarily unavailable', 502, 'storage'); }
    if (saved) {
      let data;
      try { data = approvedMetadata(saved.data, this.activePolicy); }
      catch { return registryError('Update service is temporarily unavailable', 502, 'approval'); }
      saved = data ? { ...saved, data } : null;
    }
    if (saved && now - saved.at < (suffix === 'latest' ? 120000 : 300000)) return Response.json(saved.data);
    if (now >= this.cooldown) {
      let pending = this.pending.get(key);
      if (!pending) {
        pending = this.refresh(suffix, key, now);
        this.pending.set(key, pending);
      }
      try { saved = await pending; }
      catch (failure) {
        this.cooldown = Date.now() + 30000;
        this.lastFailure = failure instanceof RegistryFailure ? failure.message : 'Registry refresh failed';
        this.lastFailureStage = failure instanceof RegistryFailure ? failure.stage : 'refresh';
      }
      finally { this.pending.delete(key); }
      if (saved && saved.at === now) return Response.json(saved.data);
      // Other requests may have shared this refresh with an earlier start time.
      if (saved && Date.now() - saved.at < 120000) return Response.json(saved.data);
    }
    if (url.searchParams.get('download') === '1' && saved && now - saved.at < 86400000) {
      return Response.json(saved.data, { headers: { 'X-Wenku-Stale': '1' } });
    }
    return registryError(this.lastFailure ?? 'GitHub release is temporarily unavailable', 503, this.lastFailureStage ?? 'refresh');
  }
  async refresh(suffix, key, now) {
    const headers = { Accept: 'application/vnd.github+json', 'User-Agent': 'Wenku8-Release-Registry', 'X-GitHub-Api-Version': '2022-11-28' };
    // Only the fixed GitHub API origin receives this optional encrypted Secret.
    if (this.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${this.env.GITHUB_TOKEN}`;
    const r = await registryStep('fetch', () => fetchHeaders((...args) => fetch(...args), `${API}${suffix}`, {
      headers, redirect: 'manual',
    }));
    if (r.status !== 200) { await r.body?.cancel().catch(() => {}); throw new RegistryFailure('http', r.status); }
    const text = await registryStep('fetch', () => r.text());
    if (text.length > 1024 * 1024) throw new RegistryFailure('json');
    const manifest = await registryStep('json', () => JSON.parse(text));
    const data = await registryStep('approval', () => approvedMetadata(manifest, this.activePolicy));
    if (!data ||
        (suffix !== 'latest' && data.tag_name !== suffix.slice(5))) throw new RegistryFailure('approval');
    const value = { data, at: now };
    await registryStep('storage', async () => {
      await this.storage.put(key, value);
      // Reuse the same verified manifest for a tagged download, avoiding a second API call.
      await this.storage.put(`release:${CACHE_NAMESPACE}:tags/${data.tag_name}`, value);
      const all = await this.storage.list({ prefix: `release:${CACHE_NAMESPACE}:tags/` });
      if (all.size > 20) {
        const oldest = [...all.entries()].sort((a, b) => a[1].at - b[1].at).slice(0, all.size - 20).map(([k]) => k);
        await this.storage.delete(oldest);
      }
    });
    return value;
  }
}

export const HOME = `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>轻小说文库 · 下载与更新</title>
<style>*{box-sizing:border-box}body{margin:0;background:#f5f4ee;color:#303633;font:16px/1.65 system-ui,-apple-system,sans-serif}main{max-width:900px;margin:auto;padding:12vh 28px 64px}small{letter-spacing:.16em;color:#65756e}h1{font-size:clamp(32px,6vw,56px);font-weight:500;letter-spacing:-.04em;margin:20px 0 12px}p{color:#65716c;max-width:630px}header{border-bottom:1px solid #d9dfd8;padding-bottom:36px;margin-bottom:32px}a{color:inherit}#files{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px;margin:26px 0 42px}.file{display:flex;flex-direction:column;gap:12px;padding:24px;background:#ffffffa8;border:1px solid #ffffff;border-radius:20px;text-decoration:none;transition:transform .2s,background .2s}.file:hover{transform:translateY(-3px);background:#fff}.file b{font-size:18px;font-weight:550}.file span{overflow-wrap:anywhere;color:#6c7970;font-size:14px}.file em{font-style:normal;color:#395f4e;margin-top:8px;font-size:14px}footer{font-size:13px;color:#79827b;display:flex;gap:24px;flex-wrap:wrap}.status{font-size:14px;color:#536a5c}pre{font-size:13px;overflow:auto;background:#e9ece5;padding:18px;border-radius:12px}
.sponsor{display:grid;grid-template-columns:64px minmax(0,1fr) auto;align-items:center;gap:22px;max-width:640px;margin:26px 0 8px;padding:24px;background:#ffffffa8;border:1px solid #dfe2d8;border-radius:18px;color:#25332e;text-decoration:none;transition:background .2s,border-color .2s}.sponsor:hover{background:#fff;border-color:#c7d2c3}.sponsor:focus-visible{outline:3px solid #7656b8;outline-offset:4px}.sponsor-art{width:64px;height:64px;display:block}.sponsor-title{font-size:28px;font-weight:600;line-height:1.3}.sponsor-cta{display:flex;align-items:center;justify-content:center;gap:20px;min-height:48px;padding:8px 22px;border-radius:24px;background:#7656b8;color:#fff;font-size:18px;font-weight:600;white-space:nowrap}.sponsor-cta svg{width:20px;height:20px}.sponsor-note{font-size:14px;margin:0 0 24px}
@media(max-width:480px){main{padding:64px 20px 48px}.sponsor{grid-template-columns:44px minmax(0,1fr) auto;gap:12px;padding:16px}.sponsor-art{width:44px;height:44px}.sponsor-title{font-size:20px}.sponsor-cta{gap:10px;min-height:42px;padding:8px 14px;font-size:16px}.sponsor-cta svg{width:16px;height:16px}}@media(prefers-reduced-motion:reduce){.sponsor{transition:none}}
</style>
<main><header><small>WENKU8 / READING ARCHIVE</small><h1>把故事，留在手边。</h1>
<a class="sponsor" href="https://afdian.com/a/mikufoxxx" target="_blank" rel="noopener noreferrer" aria-label="通过爱发电赞助支持开发者">
  <svg class="sponsor-art" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" aria-hidden="true">
    <rect width="64" height="64" rx="17" fill="#e6ebdf"/>
    <g fill="none" stroke="#617967" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M32 22c-6-4-12-5-20-3v25c8-2 14-1 20 3 6-4 12-5 20-3V19c-8-2-14-1-20 3Z"/><path d="M32 23v23M17 26c4-.5 7 0 10 2M17 33c4-.5 7 0 10 2M37 28c3-2 6-2.5 10-2M37 35c3-2 6-2.5 10-2"/></g>
    <path d="M48 12c-2.2-3.2-7-1.5-6.5 2.1.3 2.2 3.8 4.7 6.5 6.9 2.7-2.2 6.2-4.7 6.5-6.9.5-3.6-4.3-5.3-6.5-2.1Z" fill="#7656b8"/>
  </svg>
  <span class="sponsor-title">支持这个项目</span>
  <span class="sponsor-cta">爱发电<svg viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M4 16 16 4M5 4h11v11" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>
</a>
<p class="sponsor-note">赞助完全自愿，所有功能仍免费使用。</p>
<p><strong>本项目仅为第三方阅读客户端，提供阅读界面与本地书籍管理，不运营在线书库、不自行发布小说资源。在线内容及可读状态一切以 Wenku8 为准；不提供因版权限制而停止开放的在线书籍阅读。</strong></p><p><strong>本项目完全免费，不出售会员、激活码或功能解锁服务。</strong>请认准项目仓库。升级前请备份原书和阅读记录。</p><p>轻小说文库 · Android、iOS 与 HarmonyOS。在线发现、离线阅读、本地书库与自然听书，以轻盈的玻璃界面承载每一页故事。</p><p>分类阅读统计 · 八套图片报告 · 阅读日历与纪念 · 独立配置桌面小组件 · 离线词典 · S3 同步</p><p><strong>重要说明：本 APP 以后只保留轻小说文库源和本地导入功能，不再支持任何其他源以及自定义书源。</strong></p></header><section aria-label="安装说明"><h2>选择你的设备</h2><p>Android 为正式签名版，近年的手机和平板优先选择 ARM64。iOS IPA 与 HarmonyOS HAP 未签名，需要自行签名后安装。升级前请备份重要数据。</p></section><div class="status" id="status">正在读取最新版本…</div><section id="releases"><div id="files"></div></section><details><summary>本版更新说明</summary><pre id="release-notes" style="white-space:pre-wrap">正在读取…</pre></details><br><footer><a href="https://github.com/mikufoxxx/Wenku8_Flutter">项目仓库 ↗</a><a href="https://github.com/mikufoxxx/Wenku8_Flutter/releases">版本页面 ↗</a><span>轻小说文库 · Android / iOS / HarmonyOS</span></footer></main>
<script>
async function read(url, method='GET') {
  const controller = new AbortController(), timer = setTimeout(()=>controller.abort(), 8000);
  try { const r=await fetch(url,{method,signal:controller.signal,cache:'no-store'}); if(!r.ok)throw Error(); return method==='HEAD'?true:await r.json(); }
  finally {clearTimeout(timer)}
}
const approved=${JSON.stringify(Object.fromEntries(Object.entries(APPROVED_RELEASES).filter(([tag]) => approvedTag(tag))))};
async function latest(){if(Object.keys(approved).length===0)throw Error();try{return await read('/api/releases/latest')}catch{return await read('https://api.github.com/repos/mikufoxxx/Wenku8_Flutter/releases/latest')}}
function renderFiles(d, mobileOnly=false) {
  if(d.draft||d.prerelease||!approved[d.tag_name])throw Error();
  const host=document.getElementById('files');
  for(const a of d.assets||[]){
    if(mobileOnly&&!/\\.(ipa|hap)$/.test(a.name))continue;
    if(!/\\.(apk|ipa|hap|zip)$/.test(a.name)||!Number.isSafeInteger(a.id)||!approved[d.tag_name].includes(a.id))continue;
    const u=new URL(a.browser_download_url);
    if(u.origin!=='https://github.com'||u.username||u.password||u.search||u.hash||!u.pathname.startsWith('/mikufoxxx/Wenku8_Flutter/releases/download/'))continue;
    const link=document.createElement('a');link.className='file';link.href=u.pathname+'?asset='+a.id;
    const b=document.createElement('b');b.textContent=a.name.endsWith('.ipa')?'iOS · 未签名 IPA':a.name.endsWith('.hap')?'HarmonyOS · 未签名 HAP':a.name.endsWith('-source.zip')?'源代码':a.name.includes('arm64-v8a')?'Android · ARM64':a.name.includes('armeabi-v7a')?'Android · ARMv7':a.name.includes('x86_64')?'Android · x86_64':'Android · 通用';
    const s=document.createElement('span');s.textContent=d.tag_name+' · '+(a.size/1048576).toFixed(1)+' MB';
    const e=document.createElement('em');e.textContent='下载 ↓';link.append(b,s,e);host.append(link);
    let busy=false;
    link.addEventListener('click',async event=>{
      if(event.ctrlKey||event.metaKey||event.shiftKey||event.altKey)return;
      event.preventDefault();if(busy)return;busy=true;e.textContent='准备下载…';
      let target=link.href;
      try{await read(target,'HEAD')}catch{target=u.href}
      window.location.assign(target);busy=false;e.textContent='下载 ↓';
    });
  }
}
latest().then(async d=>{
  if(d.draft||d.prerelease||!approved[d.tag_name])throw Error();
  document.getElementById('status').textContent=d.tag_name+' · 最新正式版本';
  document.getElementById('release-notes').textContent=d.body||'此版本未提供更新说明。';
  renderFiles(d);
  for(const [platform,extension] of [['ios','.ipa'],['harmony','.hap']]){
    if((d.assets||[]).some(a=>a.name.endsWith(extension)&&approved[d.tag_name].includes(a.id)))continue;
    try {
      const mobile=await read('/api/releases/'+platform);
      renderFiles({...mobile,assets:mobile.assets.filter(a=>a.name.endsWith(extension))},true);
    }catch{
      const message=document.createElement('p');
      const link=document.createElement('a');link.href='https://github.com/mikufoxxx/Wenku8_Flutter/releases';link.textContent=(platform==='ios'?'iOS':'HarmonyOS')+' 下载暂未加载，前往发布页 →';message.append(link);document.getElementById('files').append(message);
    }
  }
}).catch(()=>{document.getElementById('status').textContent=Object.keys(approved).length===0?'暂无正式版本供下载。':'暂时无法读取版本，请稍后刷新。';document.getElementById('release-notes').textContent='暂无更新说明。'})
</script></html>`;
