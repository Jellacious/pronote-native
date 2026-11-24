# PronoteNative

Client macOS natif en Swift / SwiftUI pour Pronote, propulsé par un bridge Node.js [Pawnote](https://github.com/LiterateInk/Pawnote) compatible PRONOTE 2026.

## Fonctionnalités

- **Connexion par QR code** : collage depuis le presse-papiers (`⌘V`), glisser-déposer, sélection de fichier ou saisie JSON + code PIN à 4 chiffres.
- **Accueil** : carte « En ce moment » en direct avec barre de progression, prochains cours, devoirs à venir, dernières notes et pense-bête local persistant.
- **Emploi du temps** : grille style Apple Calendrier, badge Semaine A/B, détails des cours (salle, professeurs, groupes), ligne d'heure actuelle et navigation fluide au trackpad.
- **Devoirs & Contenus de cours** : filtre par matière, suivi de complétion et ouverture des pièces jointes (PDF, vidéos, liens).
- **Notes** : calcul automatique de la moyenne générale pondérée `/20` (avec gestion des bonus et barèmes), vue chronologique ou par matière.
- **Vie scolaire** : total des heures manquées, absences, retards et filtre des justificatifs.
- **Discussions & Informations** : lecture, réponse aux discussions, marquage automatique comme lu et pièces jointes.
- **Menus** : affichage hebdomadaire déjeuner / dîner avec étiquettes alimentaires.
- **Cache local & protection anti rate-limit** : chargement multi-semaines groupé, cache disque avec TTL configurable et limitation des requêtes.

## Prérequis

- macOS 14.0+ (Sonoma ou plus récent)
- Swift 6.0+ (Xcode / Command Line Tools)
- Node.js 20+

## Installation et lancement

```bash
cd bridge && npm install
cd ..
swift run
```

Pour compiler en mode release :

```bash
swift build -c release
```
