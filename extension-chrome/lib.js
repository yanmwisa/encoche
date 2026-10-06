// Fonctions pures de l'extension : sans effet de bord, testées par check.sh.
// Chargées par le service worker (importScripts) et par le test (require).

const MAX_TABS = 8
const MAX_TITLE = 80

function clampVolume(value) {
  const rounded = Math.round(Number(value))
  return Number.isFinite(rounded) ? Math.min(100, Math.max(0, rounded)) : 100
}

function hostOf(url) {
  try {
    return new URL(url).hostname
  } catch {
    return ''
  }
}

// Ce que l'extension annonce à l'app : seuls les onglets qui jouent du son, avec leur titre, leur site et le volume réglé.
function tabsMessage(tabs, volumes) {
  const playing = tabs
    .filter(tab => tab.audible === true && Number.isInteger(tab.id))
    .slice(0, MAX_TABS)
    .map(tab => ({
      id: tab.id,
      title: String(tab.title || '').slice(0, MAX_TITLE),
      host: hostOf(tab.url || ''),
      volume: volumes.has(tab.id) ? volumes.get(tab.id) : 100,
    }))
  return { type: 'tabs', tabs: playing }
}

// L'ordre de l'app : tout ce qui n'a pas exactement cette forme est ignoré.
function parseOrder(message) {
  if (!message || message.type !== 'setVolume') return null
  if (!Number.isInteger(message.tabId) || message.tabId < 0) return null
  return { tabId: message.tabId, volume: clampVolume(message.volume) }
}

if (typeof module !== 'undefined') module.exports = { clampVolume, hostOf, tabsMessage, parseOrder }
