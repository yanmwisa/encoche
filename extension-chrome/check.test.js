const { clampVolume, hostOf, tabsMessage, parseOrder } = require('./lib.js')

let passed = 0
let failed = 0
const check = (name, condition) => {
  if (condition) { passed += 1; console.log(`OK   ${name}`) } else { failed += 1; console.log(`ECHEC ${name}`) }
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b)

check('volume borné entre 0 et 100', clampVolume(-4) === 0 && clampVolume(250) === 100 && clampVolume(41.6) === 42)
check('volume illisible : 100 (la page n\'est pas touchée)', clampVolume('fort') === 100 && clampVolume(undefined) === 100)
check('site d\'un onglet', hostOf('https://www.youtube.com/watch?v=x') === 'www.youtube.com' && hostOf('pas une adresse') === '')

const tabs = [
  { id: 1, audible: true, title: 'Mix', url: 'https://www.youtube.com/watch?v=x' },
  { id: 2, audible: false, title: 'Muet', url: 'https://example.com' },
  { id: 3, audible: true, title: 'Radio', url: 'https://open.spotify.com/' },
]
check('seuls les onglets qui jouent du son sont annoncés', same(tabsMessage(tabs, new Map()).tabs.map(tab => tab.id), [1, 3]))
check('volume réglé repris, sinon 100', same(tabsMessage(tabs, new Map([[3, 40]])).tabs.map(tab => tab.volume), [100, 40]))
check('titre borné à 80 caractères', tabsMessage([{ id: 1, audible: true, title: 'x'.repeat(300), url: '' }], new Map()).tabs[0].title.length === 80)
check('huit onglets au plus', tabsMessage(Array.from({ length: 20 }, (_, id) => ({ id, audible: true })), new Map()).tabs.length === 8)
check('un onglet sans numéro est ignoré', tabsMessage([{ audible: true }, { id: 'x', audible: true }], new Map()).tabs.length === 0)
check('ordre de l\'app lu', same(parseOrder({ type: 'setVolume', tabId: 12, volume: 40 }), { tabId: 12, volume: 40 }))
check('ordre refusé : mauvais type, numéro invalide, vide', parseOrder({ type: 'x', tabId: 1, volume: 1 }) === null && parseOrder({ type: 'setVolume', tabId: -1, volume: 1 }) === null && parseOrder({ type: 'setVolume', tabId: '5', volume: 1 }) === null && parseOrder(null) === null)
check('ordre : volume borné', parseOrder({ type: 'setVolume', tabId: 1, volume: 900 }).volume === 100)

console.log(`\n${passed} réussis, ${failed} échec(s)`)
process.exit(failed === 0 ? 0 : 1)
