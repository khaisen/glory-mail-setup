<?php
// Script to test Roundcube login directly
// Save to /var/www/roundcube/check-login.php

define('INSTALL_PATH', realpath(dirname(__FILE__)) . '/');
require_once INSTALL_PATH . 'program/include/iniset.php';

// Enable error reporting
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Check if form was submitted
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = isset($_POST['username']) ? $_POST['username'] : '';
    $password = isset($_POST['password']) ? $_POST['password'] : '';
    
    if (empty($username) || empty($password)) {
        $error = "Please enter both username and password";
    } else {
        // Initialize Roundcube app
        $rcmail = rcmail::get_instance();
        
        // Try to connect to IMAP directly
        $imap_host = $rcmail->config->get('default_host', 'localhost');
        $imap_port = 143;
        $use_ssl = false;
        
        echo "<div style='background:#333; color:#fff; padding:10px; margin:10px 0; font-family:monospace;'>";
        echo "Attempting direct IMAP connection to: $imap_host:$imap_port<br>";
        
        // Try direct socket connection
        $socket = @fsockopen(($use_ssl ? 'ssl://' : '') . $imap_host, $imap_port, $errno, $errstr, 5);
        if (!$socket) {
            echo "SOCKET ERROR: ($errno) $errstr<br>";
        } else {
            echo "Socket connection: SUCCESS<br>";
            
            // Read greeting
            $greeting = fgets($socket, 1024);
            echo "IMAP greeting: " . htmlspecialchars($greeting) . "<br>";
            
            // Try login
            $login_cmd = "A1 LOGIN \"$username\" \"$password\"\r\n";
            echo "Sending: A1 LOGIN \"$username\" ********<br>";
            fwrite($socket, $login_cmd);
            $response = fgets($socket, 1024);
            echo "Response: " . htmlspecialchars($response) . "<br>";
            
            // Logout
            fwrite($socket, "A2 LOGOUT\r\n");
            fclose($socket);
        }
        echo "</div>";
        
        // Now try Roundcube's authentication
        echo "<div style='background:#333; color:#fff; padding:10px; margin:10px 0; font-family:monospace;'>";
        echo "Attempting Roundcube IMAP authentication<br>";
        
        try {
            // Load required classes
            require_once INSTALL_PATH . 'program/lib/Roundcube/rcube_imap.php';
            require_once INSTALL_PATH . 'program/lib/Roundcube/rcube_imap_generic.php';
            
            // Create IMAP object
            $imap = new rcube_imap_generic();
            $imap->set_debug(true);
            
            // Connect
            $result = $imap->connect($imap_host, $username, $password, $imap_port, $use_ssl ? 'ssl' : null);
            
            if ($result) {
                echo "Roundcube IMAP authentication: SUCCESS<br>";
                $folders = $imap->list_folders();
                echo "Available folders: " . implode(', ', $folders) . "<br>";
                $imap->disconnect();
            } else {
                echo "Roundcube IMAP authentication: FAILED<br>";
                echo "Error: " . $imap->error() . "<br>";
            }
        } catch (Exception $e) {
            echo "EXCEPTION: " . $e->getMessage() . "<br>";
        }
        echo "</div>";
        
        // Now try full Roundcube login
        echo "<div style='background:#333; color:#fff; padding:10px; margin:10px 0; font-family:monospace;'>";
        echo "Attempting full Roundcube login<br>";
        
        try {
            // Initialize login
            $auth = $rcmail->plugins->exec_hook('authenticate', array(
                'host' => $imap_host,
                'user' => $username,
                'pass' => $password,
                'cookiecheck' => true,
                'valid' => true
            ));
            
            if ($auth['valid'] && !$auth['abort']) {
                $login = $rcmail->login($auth['user'], $auth['pass'], $auth['host'], $auth['cookiecheck']);
                
                if ($login) {
                    echo "Full Roundcube login: SUCCESS<br>";
                    $rcmail->logout_actions();
                    $rcmail->kill_session();
                } else {
                    echo "Full Roundcube login: FAILED<br>";
                    echo "Error: " . $rcmail->get_error() . "<br>";
                }
            } else {
                echo "Authentication hook failed<br>";
                echo "Error: " . ($auth['error'] ?? 'Unknown error') . "<br>";
            }
        } catch (Exception $e) {
            echo "EXCEPTION: " . $e->getMessage() . "<br>";
        }
        echo "</div>";
    }
}
?>

<!DOCTYPE html>
<html>
<head>
    <title>Roundcube Login Test</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background-color: #f5f5f5;
            margin: 0;
            padding: 20px;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #0078d7;
        }
        .form-group {
            margin-bottom: 15px;
        }
        label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }
        input[type="text"],
        input[type="password"] {
            width: 100%;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
            box-sizing: border-box;
        }
        button {
            background-color: #0078d7;
            color: white;
            border: none;
            padding: 10px 15px;
            border-radius: 4px;
            cursor: pointer;
        }
        .error {
            color: red;
            margin-bottom: 15px;
        }
        .info {
            background-color: #f0f0f0;
            padding: 10px;
            border-radius: 4px;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Roundcube Login Test</h1>
        
        <div class="info">
            This tool tests Roundcube login in multiple ways to diagnose issues.
        </div>
        
        <?php if (isset($error)): ?>
            <div class="error"><?php echo $error; ?></div>
        <?php endif; ?>
        
        <form method="post">
            <div class="form-group">
                <label for="username">Email Address:</label>
                <input type="text" id="username" name="username" value="<?php echo isset($_POST['username']) ? htmlspecialchars($_POST['username']) : ''; ?>">
            </div>
            
            <div class="form-group">
                <label for="password">Password:</label>
                <input type="password" id="password" name="password">
            </div>
            
            <button type="submit">Test Login</button>
        </form>
        
        <div class="info" style="margin-top: 20px;">
            <h3>Server Information:</h3>
            <p>PHP Version: <?php echo phpversion(); ?></p>
            <p>Roundcube Version: <?php echo RCMAIL_VERSION; ?></p>
            <p>Default IMAP Host: <?php echo rcmail::get_instance()->config->get('default_host', 'Not configured'); ?></p>
            <p>Default SMTP Server: <?php echo rcmail::get_instance()->config->get('smtp_server', 'Not configured'); ?></p>
        </div>
    </div>
</body>
</html>