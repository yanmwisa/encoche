// Dans chaque page : règle le volume des éléments audio et vidéo sur ordre de l'extension.
// Par défaut la page n'est pas touchée ; le volume n'est imposé que tant que l'utilisateur l'a baissé,
// et rendu à la page dès qu'il revient à 100.
// Injecté aussi à la demande par l'extension : une seconde injection dans la même page ne fait rien.
if (!globalThis.__encocheVolumeInstalled) {
  globalThis.__encocheVolumeInstalled = true

  let level = 1
  let isEnforced = false

  function applyTo(element) {
    if (isEnforced && element.volume !== level) element.volume = level
  }

  function applyToAll() {
    document.querySelectorAll('video, audio').forEach(applyTo)
  }

  // Les lecteurs ajoutent leurs éléments après coup, et certains remettent leur propre volume : on réapplique.
  new MutationObserver(applyToAll).observe(document, { childList: true, subtree: true })
  document.addEventListener(
    'volumechange',
    event => {
      if (event.target instanceof HTMLMediaElement) applyTo(event.target)
    },
    true,
  )

  chrome.runtime.onMessage.addListener(message => {
    if (!message || message.type !== 'encoche-volume') return
    const percent = Math.min(100, Math.max(0, Math.round(Number(message.volume))))
    if (!Number.isFinite(percent)) return
    level = percent / 100
    isEnforced = percent < 100
    if (isEnforced) {
      applyToAll()
    } else {
      document.querySelectorAll('video, audio').forEach(element => {
        element.volume = 1
      })
    }
  })
}
