const $ = (id) => document.getElementById(id);
const money = (n) => { const v = Number(n || 0); return '$' + (v !== 0 && Math.abs(v) < 0.01 ? v.toFixed(6) : v.toFixed(2)); };
const when = (ts) => new Date(ts * 1000).toLocaleString();
async function api(path, options) {
  const res = await fetch(path, options);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error?.message || 'Request failed');
  return data;
}
async function load() {
  const me = await api('/api/me');
  const usage = await api('/api/usage');
  $('fig-balance').textContent = me.balance_display;
  $('fig-free').textContent = Number(me.free_tokens).toLocaleString();
  $('fig-rpm').textContent = me.rpm_limit;
  const rows = usage.data.map((row) => '<tr><td class="muted">' + when(row.created_at) + '</td><td>' + row.model + '</td><td class="muted">' + row.endpoint + '</td><td class="num">' + row.input_tokens + '</td><td class="num">' + row.output_tokens + '</td><td class="num">' + money(row.cost_micros / 1000000) + '</td><td class="num muted">' + row.latency_ms + '</td></tr>').join('');
  $('usage-body').innerHTML = rows || '<tr><td colspan="7" class="empty">No requests yet. Your first call will appear here.</td></tr>';
}
async function loadKeys() {
  const keys = await api('/api/keys');
  const rows = keys.data.map((key) => '<tr><td>' + key.name + '</td><td class="id">' + key.prefix + '</td><td class="num">' + money(key.spent) + '</td><td class="muted">' + (key.last_used_at ? when(key.last_used_at) : 'never') + '</td><td class="row-actions"><button class="danger" data-revoke="' + key.id + '">Revoke</button></td></tr>').join('');
  $('keys-body').innerHTML = rows || '<tr><td colspan="5" class="empty">No keys yet. Create one above.</td></tr>';
  document.querySelectorAll('[data-revoke]').forEach((button) => {
    button.addEventListener('click', async () => {
      if (!confirm('Revoke this key? Programs using it stop working immediately.')) return;
      await api('/api/keys/' + button.dataset.revoke, { method: 'DELETE' });
      loadKeys();
    });
  });
}
$('key-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const created = await api('/api/keys', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: $('key-name').value }) });
  $('key-secret').innerHTML = '<div class="notice good" style="margin-bottom:12px">Copy this key now. It is not stored anywhere in readable form.<div class="secret" style="margin-top:10px">' + created.secret + '</div></div>';
  $('key-name').value = '';
  loadKeys();
});
$('signout').addEventListener('click', async () => { await fetch('/api/auth/logout', { method: 'POST' }); location.href = '/login'; });
load();
loadKeys();
