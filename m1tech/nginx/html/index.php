<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Statut Infrastructure M1Tech</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1e1e2e; color: #cdd6f4; text-align: center; padding-top: 50px; }
        .card { background: #313244; padding: 30px; border-radius: 10px; display: inline-block; box-shadow: 0 4px 10px rgba(0,0,0,0.3); }
        .status { font-weight: bold; padding: 10px 20px; border-radius: 5px; display: inline-block; margin-top: 15px; }
        .success { background: #a6e3a1; color: #11111b; }
        .error { background: #f38ba8; color: #11111b; }
    </style>
</head>
<body>

<div class="card">
    <h1>Statut de la stack de Nolan</h1>
    <p>Vérification de la connexion à la base de données MariaDB...</p>

    <?php
    $host = '172.30.0.10';  // IP de m1tech-mariadb
    $db   = 'm1tech_db';
    $user = 'nolan';
    $pass = 'azerty'; // Mets le vrai mot de passe ici

    try {
        $pdo = new PDO("mysql:host=$host;dbname=$db;charset=utf8", $user, $pass);
        echo '<div class="status success">✔ Connexion Réussie à MariaDB !</div>';
    } catch (PDOException $e) {
        echo '<div class="status error">✘ Échec de la connexion : ' . $e->getMessage() . '</div>';
    }
    ?>
</div>

</body>
</html>
