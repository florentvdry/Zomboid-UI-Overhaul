# Publication V1 — GitHub et Steam Workshop

Le projet utilise **1.0.0**. Le nom retenu est **Zomboid UI Overhaul** ;
l’identifiant technique reste `N26_UIOverhaul`. La licence MIT a été choisie par
l’auteur pour son code et ses créations propres.

## Derniers éléments éditoriaux

1. Relancer le jeu, contrôler les derniers correctifs et remplacer les captures
   selon [le guide](screenshots/README.md).
2. Le nom final et la signature sont documentés dans [l’identité du mod](NAMES.fr.md).
3. Après les envois, ajouter les vraies URL GitHub/Workshop au README et à la
   description Steam. Aucun identifiant de publication n’est inventé.

## Préparer les archives

```powershell
npm ci
npm run i18n
npm run branding
npm run lint
npm run release
```

Dans `dist/` :

- `N26_UIOverhaul-1.0.0.zip` : installation manuelle (`42` + `common`).
- `N26_UIOverhaul-source-1.0.0.zip` : projet source.
- `N26_UIOverhaul-workshop-1.0.0.zip` : dossier d’envoi Steam avec `Contents`.
- `SHA256SUMS-1.0.0.txt` : empreintes des trois archives.

## GitHub

Le dépôt doit rester limité au dossier du mod. Les sauvegardes, bases de données,
journaux et autres mods du dossier parent n’y appartiennent pas. Le `.gitignore`
exclut dépendances, résultats de tests et archives générées.

Créer un dépôt vide sur GitHub, sans README initial. Après authentification Git,
depuis ce dossier, adapter `TON_COMPTE` et le nom du dépôt :

```powershell
git status --short
git add .
git commit -m "Prepare public release v1.0.0"
git remote add origin https://github.com/TON_COMPTE/zomboid-ui-overhaul.git
git push -u origin main
```

Après la dernière vérification en jeu, créer le tag `v1.0.0` et une Release GitHub
associée. Utiliser `publishing/RELEASE_NOTES.md`, retirer sa note de préparation
une fois le contrôle effectué et joindre le ZIP d’installation ainsi que les
empreintes. Le ZIP source est facultatif ; le ZIP Workshop sert à l’auteur.

[Procédure officielle GitHub](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github).

## Steam Workshop

Le dossier local préparé est :

```text
Zomboid/Workshop/N26_UIOverhaul/
├── preview.png             (256 × 256, moins de 1 000 000 octets)
├── workshop.txt            (visibilité initiale : private)
└── Contents/mods/N26_UIOverhaul/
    ├── 42/mod.info
    ├── 42/media/...
    ├── common/...
    └── LICENSE
```

Lancer le jeu via Steam, ouvrir **Workshop > Create and update items**, sélectionner
`N26_UIOverhaul`, vérifier titre, description et catégories, puis envoyer.
Garder d’abord la visibilité privée pour vérifier le téléchargement et l’activation.
Pour ce contrôle, mettre la copie de développement hors des dossiers scannés,
afin d’identifier sans ambiguïté la copie Workshop chargée, puis la restaurer.

Ajouter les nouvelles captures et le lien GitHub sur Steam, puis choisir la
visibilité publique quand le résultat convient.

Le jeu enregistre l’identifiant Steam dans le champ **`id=` de `workshop.txt`**
après création. Conserver ce fichier pour mettre à jour le même élément. Le champ
`version=1` décrit le format Workshop ; la version du mod est `modversion=1.0.0`
dans `42/mod.info`.

Pour une mise à jour : extraire le nouveau ZIP Workshop ailleurs, remplacer le
sous-dossier `Contents/mods/N26_UIOverhaul` de l’élément existant et actualiser
titre/description sans effacer `id=`. Ne pas mettre le ZIP, `node_modules`, `tests`
ou `tools` dans `Contents`.

[Structure et envoi depuis le jeu, forum The Indie Stone](https://theindiestone.com/forums/topic/21951-the-one-stop-tilezed-mapping-shop/).
