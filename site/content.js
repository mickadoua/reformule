/* Reformule on the shared kit: adds the dm-consulting.tech link, the French version and the Apache-2.0 footer. Requirements, privacy and download lines by Léa (DMC-630). */
window.SITE = {
  name: 'Reformule', logo: 'logo.svg',
  repo: 'https://github.com/mickadoua/reformule',
  dmcPage: { en: 'https://www.dm-consulting.tech/en/open-source/reformule', fr: 'https://www.dm-consulting.tech/fr/open-source/reformule' },
  common: { license: 'Apache-2.0', licenseUrl: 'https://github.com/mickadoua/reformule/blob/main/LICENSE' },
  download: { build: 'https://github.com/mickadoua/reformule#install' }, // no signed app: building from source (Apple Developer account = level 3)
  shots: [{ src: 'carte-clair.png', srcDark: 'carte-sombre.png', wide: true }],
  i18n: {
    en: { tagline: 'Better text, formatting intact', eyebrow: 'macOS app · Apache-2.0',
      h1: 'Better text, <em>formatting intact.</em>',
      lede: 'Reformule corrects and rephrases the text of any field on macOS, from a shortcut or a right-click. Bold, links, code and lists stay exactly where they were.',
      shotCaptions: ['Suggestion card: deletions struck through, additions highlighted'],
      featuresKicker: 'Usage', featuresTitle: 'Right where the text already is.', featuresIntro: 'No copying to another tool and back: the correction happens in the field you are typing in.',
      features: [
        { icon: 'keys', title: 'Keyboard shortcut', text: 'Right ⌘ + / by default, or any combination. Corrects the selection, or the whole field, and shows the changes in a card first.' },
        { icon: 'text', title: 'Right-click', text: 'Two entries in the Services menu: correct and rephrase, or correct only. The clipboard comes back as it was.' },
        { icon: 'shield', title: 'Structure protected', text: 'Paragraphs, bullets and nesting never go through the model. URLs and code are swapped for tokens.' }],
      downloadTitle: 'Build it yourself', downloadIntro: 'Build it from source: one command, no paid Apple account needed.',
      buildText: 'Clone the repository and follow the build steps.', downloadNote: 'Requires macOS 26 on Apple silicon and Claude Code, installed and signed in. Your text is sent to Anthropic by Claude Code, with your signed-in account, and counts against its subscription or billing.' },
    fr: { tagline: 'De meilleurs textes, mise en forme intacte', eyebrow: 'Appli macOS · Apache-2.0',
      h1: 'De meilleurs textes, <em>mise en forme intacte.</em>',
      lede: 'Reformule corrige et reformule le texte de n’importe quel champ sur macOS, par un raccourci ou un clic droit. Gras, liens, code et listes restent exactement en place.',
      shotCaptions: ['Carte de suggestion : suppressions barrées, ajouts surlignés'],
      featuresKicker: 'Usage', featuresTitle: 'Là où se trouve déjà le texte.', featuresIntro: 'Pas de copier-coller vers un autre outil : la correction se fait dans le champ où vous écrivez.',
      features: [
        { icon: 'keys', title: 'Raccourci clavier', text: '⌘ droit + / par défaut, ou toute combinaison. Corrige la sélection ou tout le champ, et montre les changements dans une carte d’abord.' },
        { icon: 'text', title: 'Clic droit', text: 'Deux entrées dans le menu Services : corriger et reformuler, ou corriger seulement. Le presse-papiers revient comme avant.' },
        { icon: 'shield', title: 'Structure protégée', text: 'Paragraphes, puces et imbrications ne passent jamais par le modèle. URL et code sont remplacés par des jetons.' }],
      downloadTitle: 'À compiler soi-même', downloadIntro: 'Compilez-la depuis les sources : une commande, sans compte Apple payant.',
      buildText: 'Clonez le dépôt et suivez les étapes de compilation.', downloadNote: 'Demande macOS 26 sur Apple silicon et Claude Code, installé et connecté. Votre texte est envoyé à Anthropic par Claude Code, avec votre compte connecté, et compte dans son abonnement ou sa facturation.' }
  }
};
