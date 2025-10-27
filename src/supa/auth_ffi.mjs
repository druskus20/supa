import { Ok, Error } from "../gleam.mjs";

export function getUrlFragment() {
  return window.location.hash.substring(1);
}

export function getStoredSession() {
  const stored = localStorage.getItem('supabase_session');
  return stored ? new Ok(stored) : new Error(undefined);
}

export function storeSession(sessionJson) {
  localStorage.setItem('supabase_session', sessionJson);
}

export function getCurrentTime() {
  return Math.floor(Date.now() / 1000);
}

export function parseJwt(token) {
  try {
    const base64Payload = token.split('.')[1]
      .replace(/-/g, '+')
      .replace(/_/g, '/');
    const paddedPayload = base64Payload + '='.repeat((4 - base64Payload.length % 4) % 4);
    const payload = JSON.parse(atob(paddedPayload));
    return new Ok(JSON.stringify(payload));
  } catch (e) {
    return new Error(undefined);
  }
}

export function clearUrlFragment() {
  if (window.history && window.history.replaceState) {
    window.history.replaceState(null, null, window.location.pathname + window.location.search);
  }
}

export function debugLog(message) {
  console.log('SUPA DEBUG:', message);
}

export function clearSession() {
  if (typeof localStorage !== 'undefined') {
    localStorage.removeItem('supabase_session');
  }
}

