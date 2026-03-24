<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->
[![forthebadge](https://forthebadge.com/images/badges/built-by-developers.svg)](https://forthebadge.com)
[![forthebadge](https://forthebadge.com/images/badges/built-with-love.svg)](https://forthebadge.com)
[![forthebadge](https://forthebadge.com/images/badges/built-with-swag.svg)](https://forthebadge.com)
[![forthebadge](https://forthebadge.com/images/badges/made-with-python.svg)](https://forthebadge.com)



<div align="center">

# 🍽️ Restaurant Checker (Alim'Confiance)

**Une application iOS native, fluide et réactive pour consulter le niveau d'hygiène des établissements de la chaîne alimentaire en France.**

[![Swift](https://img.shields.io/badge/Swift-5.9_+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-17.0_+-000000?style=flat-square&logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-100%25-blue?style=flat-square)](https://developer.apple.com/xcode/swiftui/)
[![API](https://img.shields.io/badge/API-DGAL_OpenData-success?style=flat-square)](https://dgal.opendatasoft.com/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](https://opensource.org/licenses/MIT)

<br>

<img width="312" height="312" alt="Gemini_Generated_Image_v6lkstv6lkstv6lk (1)" src="https://github.com/user-attachments/assets/3335805d-95f4-49ea-bb82-9b9be80efca4" />

</div>

## 📖 À propos du projet

**Restaurant Checker** est un projet iOS conçu pour offrir une transparence totale sur les contrôles sanitaires des restaurants, supermarchés et boulangeries en France. 
L'application interroge en temps réel les données officielles du gouvernement (DGAL) et les restitue sur une carte interactive immersive.

### ✨ Fonctionnalités principales

* 🗺️ **Carte Interactive 3D/Satellite :** Exploration fluide avec `MapKit`, ajustement dynamique des données ("Search as you pan").
* 📍 **Géolocalisation Native :** Centrage ultra-rapide sur la position de l'utilisateur.
* 🔍 **Moteur de Recherche Avancé :** Recherche par nom d'établissement ou par ville avec gestion des wildcards (recherche "Live").
* 🎛️ **Bottom Sheet Intelligente :** Filtrage instantané par activité (Restauration rapide, Boulangerie, etc.) et par niveau d'hygiène.
* 📊 **Fiches Détaillées :** Affichage de la date du dernier contrôle, adresse et évaluation avec un code couleur instinctif.
* 🚀 **Splash Screen Custom :** Écran de démarrage animé avec barre de progression native.

---

## 📸 Aperçus

<div align="center">
<img width="368" height="761" alt="Capture d’écran 2026-03-24 à 20 14 42" src="https://github.com/user-attachments/assets/1762a4e4-d258-4244-a495-b3d4ceb46cef" />
 </div>

---

## 🛠 Technologies et Architecture

Ce projet a été construit en utilisant les standards modernes d'Apple pour garantir performance et maintenabilité :

* **UI Framework :** SwiftUI (100%) avec utilisation de `GeometryReader` pour un affichage "responsive" (de l'iPhone SE au Pro Max).
* **Architecture :** Modèle **MVVM** (Model-View-ViewModel) avec `@MainActor` et `ObservableObject`.
* **Asynchronisme :** Async/Await de Swift (`Task`) et Combine pour la gestion réseau.
* **Cartographie :** `MapKit` (iOS 17+) avec gestion du `safeAreaPadding` pour une interface superposée.
* **Localisation :** `CoreLocation` avec système de callback anti-boucle infinie.

### 📡 Source des données (API)
Les données sont tirées de l'Open Data du gouvernement français :
[Alimentation : résultats des contrôles sanitaires (Alim'confiance)](https://dgal.opendatasoft.com/explore/dataset/export_alimconfiance/information/)

---

## ⚙️ Prérequis

Pour compiler et lancer cette application, vous aurez besoin de :

* Un Mac sous **macOS Ventura 13.3** (ou ultérieur).
* **Xcode 15.0** (ou ultérieur).
* Cible de déploiement : **iOS 17.0** minimum.

---

## 🚀 Installation & Lancement

1. **Cloner le dépôt**
   ```bash
   git clone [https://github.com/TonNomUtilisateur/RestaurantChecker.git](https://github.com/TonNomUtilisateur/RestaurantChecker.git)
   cd RestaurantChecker
