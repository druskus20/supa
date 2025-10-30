export function parseUrlSession() {
  if (typeof window === 'undefined') {
    return { tag: "Error", _0: null };
  }

  const fragment = window.location.hash.substring(1);

  // First try to parse from URL fragment (fresh from OAuth)
  if (fragment && fragment.includes('access_token')) {
    // Continue with URL fragment parsing below...
  } else {
    // No URL fragment, try to load from localStorage
    try {
      const stored = localStorage.getItem('supabase_session');
      if (stored) {
        const { session, user } = JSON.parse(stored);

        // Check if session is still valid (not expired)
        if (session.expires_at > Math.floor(Date.now() / 1000)) {
          return {
            tag: "Ok",
            _0: [session, user]
          };
        } else {
          // Session expired, clear it
          localStorage.removeItem('supabase_session');
        }
      }
    } catch (e) {
      console.warn('Could not load session from localStorage:', e);
      localStorage.removeItem('supabase_session');
    }

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

  // Store session in localStorage for persistence
  try {
    localStorage.setItem('supabase_session', JSON.stringify({
      session: session,
      user: user
    }));
  } catch (e) {
    console.warn('Could not store session in localStorage:', e);
  }

  // Clear the URL fragment after parsing
  if (window.history && window.history.replaceState) {
    window.history.replaceState(null, null, window.location.pathname + window.location.search);
  }

  return {
    tag: "Ok",
    _0: [session, user]
  };
}