// Release tags and exact attachment IDs require an explicit publication review.
export const APPROVED_RELEASES = Object.freeze({});
export const CACHE_NAMESPACE = 'withdrawn-20261102';

export function approvedTag(tag, policy = APPROVED_RELEASES) {
  const version = /^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$/.exec(tag);
  if (!version) return false;
  const [major, minor, patch] = version.slice(1).map(Number);
  if (major === 0 && (minor < 4 || (minor === 4 && patch <= 1))) return false;
  return Array.isArray(policy[tag]) && policy[tag].some(id => Number.isSafeInteger(id) && id > 0);
}

export function approvedMetadata(data, policy = APPROVED_RELEASES) {
  if (!data || data.draft !== false || data.prerelease !== false || !approvedTag(data.tag_name, policy)) return null;
  const assets = (data.assets ?? []).filter(asset => policy[data.tag_name].includes(asset.id));
  if (assets.length === 0) return null;
  const { zipball_url, tarball_url, upload_url, ...metadata } = data;
  return { ...metadata, assets };
}
