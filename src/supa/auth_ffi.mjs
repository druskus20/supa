export function parseUrlSession() {
  if (typeof window === 'undefined') {
    throw new Error('No window available');
  }

  const fragment = window.location.hash.substring(1);

  // First try to parse from URL fragment (fresh from OAuth)
  if (fragment && fragment.includes('access_token')) {
    console.log('Found OAuth tokens in URL fragment:', fragment);
    // Continue with URL fragment parsing below...
  } else {
    console.log('No OAuth tokens in URL fragment, checking localStorage');
    // No URL fragment, try to load from localStorage
    try {
      const stored = localStorage.getItem('supabase_session');
      if (stored) {
        const { session, user } = JSON.parse(stored);

        // Check if session is still valid (not expired)
        if (session.expires_at > Math.floor(Date.now() / 1000)) {
          console.log('Found valid session in localStorage');
          return {
            tag: "Ok",
            _0: [session, user]
          };
        } else {
          // Session expired, clear it
          console.log('Session in localStorage expired');
          localStorage.removeItem('supabase_session');
        }
      }
    } catch (e) {
      console.warn('Could not load session from localStorage:', e);
      localStorage.removeItem('supabase_session');
    }

    console.log('No valid session found');
    throw new Error('No valid session found');
  }

  const params = new URLSearchParams(fragment);
  const accessToken = params.get('access_token');
  const refreshToken = params.get('refresh_token');
  const expiresIn = params.get('expires_in');
  const tokenType = params.get('token_type');

  console.log('Parsed OAuth params:', {
    accessToken: accessToken ? 'present' : 'missing',
    refreshToken,
    expiresIn,
    tokenType
  });

  if (!accessToken) {
    console.log('No access token found in URL fragment');
    throw new Error('No access token found in URL fragment');
  }

  // Parse the JWT to get user info
  let user = null;
  try {
    console.log('Parsing JWT token...');
    // Convert base64url to base64 for atob()
    const base64Payload = accessToken.split('.')[1]
      .replace(/-/g, '+')
      .replace(/_/g, '/');
    // Add padding if needed
    const paddedPayload = base64Payload + '='.repeat((4 - base64Payload.length % 4) % 4);
    const payload = JSON.parse(atob(paddedPayload));
    user = {
      id: payload.sub || '',
      email: payload.email || '',
      created_at: new Date().toISOString()
    };
    console.log('JWT parsed successfully, user:', user);
  } catch (e) {
    console.error('Error parsing JWT:', e);
    throw new Error('Error parsing JWT: ' + e.message);
  }

  console.log('Creating session object...');
  const session = {
    access_token: accessToken,
    refresh_token: refreshToken || '',
    expires_in: parseInt(expiresIn) || 3600,
    token_type: tokenType || 'bearer',
    expires_at: Math.floor(Date.now() / 1000) + (parseInt(expiresIn) || 3600)
  };
  console.log('Session created:', session);

  // Store session in localStorage for persistence
  try {
    localStorage.setItem('supabase_session', JSON.stringify({
      session: session,
      user: user
    }));
    console.log('Session stored in localStorage successfully');
  } catch (e) {
    console.warn('Could not store session in localStorage:', e);
  }

  // Clear the URL fragment after parsing
  if (window.history && window.history.replaceState) {
    window.history.replaceState(null, null, window.location.pathname + window.location.search);
  }

  const result = [session, user]; // Gleam tuple representation
  console.log('Returning successful session result:', { session, user });
  console.log('Result structure:', result);
  // Return the tuple directly - Gleam will wrap it in Ok() automatically
  console.log('Returning tuple directly for success case:', result);
  return result;
}