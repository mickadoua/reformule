# Reformule

Corrige et reformule le texte du champ actif, dans n'importe quelle app macOS, sans perdre la mise en forme.

Un raccourci (⌘ droit + / par défaut) copie la sélection, ou tout le champ s'il n'y en a pas, la fait corriger par Claude via Claude Code, puis recolle le résultat à la place. Le gras, l'italique, les liens, le code et les listes sont conservés.

## Prérequis

- macOS 26 sur Apple silicon
- [Claude Code](https://code.claude.com) installé et connecté, avec `claude` dans `~/.local/bin`, `/opt/homebrew/bin` ou `/usr/local/bin`
- Les outils en ligne de commande Xcode (`xcode-select --install`)

## Installation

```sh
./build.sh install
open ~/Applications/Reformule.app
```

Autoriser ensuite Reformule dans Réglages Système > Confidentialité et sécurité > Accessibilité : l'app en a besoin pour lire le raccourci et envoyer ⌘C / ⌘V.

L'app est signée ad hoc, donc macOS la considère comme une nouvelle app après chaque compilation. Il faut alors retirer l'ancienne autorisation et la redonner :

```sh
tccutil reset Accessibility io.github.mickadoua.reformule
```

## Réglages

Tout se règle depuis l'icône ✎ de la barre des menus :

- **Modèle** : Fable, Opus (par défaut), Sonnet ou Haiku, dans leur dernière version via les alias de Claude Code
- **Effort** : low (par défaut), medium ou high
- **Mode** : corriger et reformuler, ou corriger seulement
- **Raccourci** : enregistré au clavier, en distinguant les touches de gauche et de droite
- **Lancement à l'ouverture de session**

## Fonctionnement

1. Reformule envoie ⌘C. Si rien n'est copié, il sélectionne tout le champ (⌘A) puis copie.
2. Il découpe le contenu en blocs (paragraphes, puces, numéros) et garde lui-même la structure. Les URL et le code sont remplacés par des jetons que le modèle doit recopier.
3. `claude -p` reçoit les blocs et renvoie autant de blocs corrigés, au format JSON. L'appel n'utilise ni outils, ni serveurs MCP, ni CLAUDE.md, ni les hooks de l'utilisateur.
4. Un bloc dont les marqueurs de mise en forme ou les jetons ont changé reste tel quel.
5. Reformule reconstruit le HTML, le RTF et le texte brut, colle avec ⌘V, puis restaure le presse-papiers d'origine.

## Confidentialité

Le texte est envoyé à Anthropic par Claude Code, avec le compte connecté, et décompté sur son abonnement ou sa facturation.

## Limites

- Les contenus avec images, émojis sous forme d'image ou tableaux ne sont pas modifiés.
- Le souligné, le barré et les couleurs sont perdus.
- Les mentions (@quelqu'un) de Slack ou Jira ne reçoivent pas de traitement particulier.
- Dans VS Code et JetBrains, ⌘C sans sélection copie la ligne courante : c'est elle qui est corrigée.

## Tester sans raccourci

```sh
build/Reformule.app/Contents/MacOS/Reformule --pasteboard
```

Traite le contenu du presse-papiers avec les réglages enregistrés et y écrit le résultat, sans Accessibilité.

## Licence

[MIT](LICENSE)
