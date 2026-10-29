const $ = (id) => document.getElementById(id);
const money = (n) => { const v = Number(n || 0); return '$' + (v !== 0 && Math.abs(v) < 0.01 ? v.toFixed(6) : v.toFixed(2)); };
async function api(path, options) {
  const res = await fetch(path, options);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error?.message || 'Request failed');
  return data;
}
function notice(text, bad) {
  $('admin-notice').innerHTML = '<div class="notice ' + (bad ? 'bad' : 'good') + '" style="margin-bottom:10px">' + text + '</div>';
}
async function loadOverview() {
  const data = await api('/api/admin/overview');
  $('fig-requests').textContent = Number(data.requests).toLocaleString();
  $('fig-revenue').textContent = data.revenue_display;
  $('fig-users').textContent = data.users;
  $('upstream-state').textContent = data.upstream_configured ? 'A key is configured for ' + data.upstream_base + '.' : 'No upstream key yet. Requests will fail until one is saved.';
}
async function loadModels() {
  const data = await api('/api/admin/models');
  $('model-count').textContent = data.data.length + ' models';
  const rows = data.data.map((model) => {
    const sub = model.name === model.id
      ? (model.context_window ? Number(model.context_window).toLocaleString() + ' ctx' : 'no context set')
      : model.id;
    return '<tr><td><div>' + model.name + '</div><div class="id">' + sub + '</div></td><td class="muted">' + model.provider + '</td>'
    + '<td class="num"><input data-price="in" data-id="' + model.id + '" value="' + model.input_dollars.toFixed(2) + '" ></td>'
    + '<td class="num"><input data-price="out" data-id="' + model.id + '" value="' + model.output_dollars.toFixed(2) + '" ></td>'
    + '<td><span class="tag ' + (model.status === 'active' ? 'ok' : 'off') + '">' + model.status + '</span></td>'
    + '<td class="row-actions"><button class="ghost" data-save="' + model.id + '">Save</button></td></tr>';
  }).join('');
  $('models-body').innerHTML = rows || '<tr><td colspan="6" class="empty">No models. Import the APInex catalogue to start.</td></tr>';
  document.querySelectorAll('[data-save]').forEach((button) => {
    button.addEventListener('click', async () => {
      const id = button.dataset.save;
      const inputs = document.querySelectorAll('[data-id="' + id + '"]');
      const payload = {};
      inputs.forEach((input) => { payload[input.dataset.price] = Number(input.value); });
      await api('/api/admin/models/' + encodeURIComponent(id), { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload) });
      notice('Price saved for ' + id + '.');
    });
  });
}
async function loadUsers() {
  const data = await api('/api/admin/users');
  const rows = data.data.map((user) => '<tr><td>' + user.email + '</td><td><span class="tag ' + (user.status === 'active' ? 'ok' : 'warn') + '">' + user.status + '</span></td>'
    + '<td class="num">' + user.balance_display + '</td><td class="num">' + user.requests + '</td>'
    + '<td class="row-actions"><button class="ghost" data-credit="' + user.id + '">Credit $10</button></td></tr>').join('');
  $('users-body').innerHTML = rows || '<tr><td colspan="5" class="empty">No accounts yet.</td></tr>';
  document.querySelectorAll('[data-credit]').forEach((button) => {
    button.addEventListener('click', async () => {
      await api('/api/admin/users/' + button.dataset.credit + '/credit', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ dollars: 10 }) });
      loadUsers(); loadOverview();
    });
  });
}
$('import').addEventListener('click', async () => {
  $('import').disabled = true;
  try {
    const result = await api('/api/admin/models/import', { method: 'POST' });
    notice('Imported ' + result.imported + ' models from APInex.');
    loadModels();
  } catch (error) { notice(error.message, true); }
  $('import').disabled = false;
});
$('add-model').addEventListener('click', async () => {
  const id = prompt('Model id, exactly as the upstream names it (for example gpt/4o-mini):');
  if (!id) return;
  try {
    await api('/api/admin/models', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ id }) });
    notice('Added ' + id + '. Set its price in the table.');
    loadModels();
  } catch (error) { notice(error.message, true); }
});
$('upstream-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  await api('/api/admin/upstream', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ key: $('upstream-key').value }) });
  $('upstream-key').value = '';
  notice('Upstream key saved.');
  loadOverview();
});
$('signout').addEventListener('click', async () => { await fetch('/api/admin/logout', { method: 'POST' }); location.href = '/admin'; });
loadOverview(); loadModels(); loadUsers();
