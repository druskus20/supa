export function parseUrlSession() {
  if (typeof window === 'undefined') {
    return { tag: "Error", _0: null };
  }

  const fragment = window.location.hash.substring(1);
  if (!fragment) {
    return { tag: "Error", _0: null };
  }

  const params = new URLSearchParams(fragment);
  const accessToken = params.get('access_token');
  const refreshToken = params.get('refresh_token');
  const expiresIn = params.get('expires_in');
  const tokenType = params.get('token_type');

  if (!accessToken) {
    return { tag: "Error", _0: null };
  }

  // Parse the JWT to get user info
  let user = null;
  try {
    const payload = JSON.parse(atob(accessToken.split('.')[1]));
    user = {
      id: payload.sub || '',
      email: payload.email || '',
      created_at: new Date().toISOString()
    };
  } catch (e) {
    return { tag: "Error", _0: null };
  }

  const session = {
    access_token: accessToken,
    refresh_token: refreshToken || '',
    expires_in: parseInt(expiresIn) || 3600,
    token_type: tokenType || 'bearer',
    expires_at: Math.floor(Date.now() / 1000) + (parseInt(expiresIn) || 3600)
  };

  // Clear the URL fragment after parsing
  if (window.history && window.history.replaceState) {
    window.history.replaceState(null, null, window.location.pathname + window.location.search);
  }

  return {
    tag: "Ok",
    _0: [session, user]
  };
}