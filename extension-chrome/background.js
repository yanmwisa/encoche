// Service worker : annonce à l'app Encoche les onglets qui jouent du son et applique ses ordres de volume.
// Le lien passe par la messagerie native (hôte local « local.encoche.chrome »), jamais par le réseau.
importScripts('lib.js')

const HOST = 'local.encoche.chrome'
const REPORT_EVERY_MS = 2000
const RETRY_MIN_MS = 5000
const RETRY_MAX_MS = 60000

const volumes = new Map()
let port = null
let retryMs = RETRY_MIN_MS

// Le service worker peut être endormi puis réveillé : les réglages survivent dans la session du navigateur.
const restored = chrome.storage.session
  .get('volumes')
  .then(({ volumes: saved }) => {
    for (const [id, volume] of Object.entries(saved || {})) volumes.set(Number(id), volume)
  })
  .catch(() => undefined)

function remember() {
  void chrome.storage.session.set({ volumes: Object.fromEntries(volumes) }).catch(() => undefined)
}

// Chrome n'injecte le script de contenu que dans les pages chargées APRÈS l'installation de l'extension :
// un onglet déjà ouvert (YouTube) n'en a pas. On l'y injecte avant d'envoyer l'ordre ; content.js se protège d'une double injection.
async function applyToPage(tabId, volume) {
  try {
    await chrome.scripting.executeScript({ target: { tabId, allFrames: true }, files: ['content.js'] })
    await chrome.tabs.sendMessage(tabId, { type: 'encoche-volume', volume })
  } catch (error) {
    // Pages que Chrome interdit (chrome://, boutique d'extensions) ou onglet fermé : on le dit dans la console du service worker.
    console.warn(`Encoche : volume non appliqué à l'onglet ${tabId} :`, String(error))
  }
}

async function report() {
  if (port === null) return
  await restored
  const tabs = await chrome.tabs.query({ audible: true })
  try {
    port.postMessage(tabsMessage(tabs, volumes))
  } catch {
    // Le lien vient de se fermer : la reconnexion s'en occupe.
  }
}

function onOrder(message) {
  retryMs = RETRY_MIN_MS
  const order = parseOrder(message)
  if (order === null) return
  volumes.set(order.tabId, order.volume)
  remember()
  void applyToPage(order.tabId, order.volume)
  void report()
}

function connect() {
  try {
    port = chrome.runtime.connectNative(HOST)
  } catch {
    port = null
    setTimeout(connect, retryMs)
    return
  }
  port.onMessage.addListener(onOrder)
  port.onDisconnect.addListener(() => {
    void chrome.runtime.lastError
    port = null
    retryMs = Math.min(retryMs * 2, RETRY_MAX_MS)
    setTimeout(connect, retryMs)
  })
  void report()
}

chrome.tabs.onUpdated.addListener((tabId, change) => {
  if ('audible' in change) void report()
  if (change.status === 'complete' && volumes.has(tabId)) void applyToPage(tabId, volumes.get(tabId))
})

chrome.tabs.onRemoved.addListener(tabId => {
  volumes.delete(tabId)
  remember()
  void report()
})

setInterval(report, REPORT_EVERY_MS)
connect()
