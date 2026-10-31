// Opens the spec-watch issue with the workflow's own GITHUB_TOKEN, at most one open issue per title.
export const LABEL = 'upstream-api';

export async function ensureIssue({ repository, token, title, body, fetch = globalThis.fetch }) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository ?? '')) throw new Error('GITHUB_REPOSITORY must be owner/name');
  if (!token) throw new Error('GITHUB_TOKEN is not set');
  const api = `https://api.github.com/repos/${repository}`;
  const headers = { accept: 'application/vnd.github+json', authorization: `Bearer ${token}`, 'x-github-api-version': '2022-11-28' };
  const listed = await fetch(`${api}/issues?state=open&per_page=100`, { headers });
  if (!listed.ok) throw new Error(`GitHub issues: ${listed.status}`);
  const existing = (await listed.json()).find(issue => issue.title === title && !issue.pull_request);
  if (existing) return { created: false, number: existing.number, url: existing.html_url };
  const created = await fetch(`${api}/issues`, {
    method: 'POST',
    headers: { ...headers, 'content-type': 'application/json' },
    body: JSON.stringify({ title, body, labels: [LABEL] }),
  });
  if (!created.ok) throw new Error(`GitHub create issue: ${created.status}`);
  const issue = await created.json();
  return { created: true, number: issue.number, url: issue.html_url };
}
