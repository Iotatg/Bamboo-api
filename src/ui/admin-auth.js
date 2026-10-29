document.getElementById('admin-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const box = document.getElementById('auth-error');
  box.hidden = true;
  const res = await fetch('/api/admin/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email: email.value, password: password.value }) });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) { box.textContent = data.error?.message || 'Sign in failed.'; box.hidden = false; return; }
  location.href = '/admin';
});
