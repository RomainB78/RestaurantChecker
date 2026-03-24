# RestaurantChecker

## Description

RestaurantChecker est une application qui permet aux utilisateurs de rechercher des restaurants, de consulter les avis et de faire des réservations en ligne. Grâce à une interface conviviale, l'application rend la découverte et la gestion des restaurants simples et efficaces.

## Caractéristiques

- **Recherche de Restaurants** : Trouvez des restaurants à proximité selon des critères spécifiques tels que le type de cuisine ou le prix.
- **Avis Utilisateurs** : Consultez les avis d'autres utilisateurs pour prendre des décisions éclairées sur les choix de restaurants.
- **Réservations En Ligne** : Réservez votre table directement à travers l'application sans tracas.
- **Favoris** : Ajoutez vos restaurants préférés pour un accès rapide.

## Architecture

L'application est construite sur une architecture en microservices, ce qui permet une évolutivité et une maintenance facilitées. Les différents services communiquent via des APIs REST et sont déployés sur des conteneurs Docker.

- **Frontend** : Développé en React.js pour une expérience utilisateur réactive.
- **Backend** : Utilise Node.js avec Express pour gérer les requêtes API et interagir avec la base de données.
- **Base de Données** : MongoDB est utilisé pour stocker les informations relatives aux restaurants et aux utilisateurs.

## Utilisation

1. Clonez le dépôt sur votre machine locale.
2. Installez les dépendances avec `npm install`.
3. Démarrez le serveur avec `npm start`.
4. Ouvrez votre navigateur et accédez à `http://localhost:3000`.

## Conclusion

RestaurantChecker vise à simplifier la manière dont les utilisateurs découvrent et interagissent avec les restaurants. Que ce soit pour une sortie improvisée ou un dîner planifié, notre application est là pour vous aider à faire le bon choix.