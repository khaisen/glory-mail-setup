<?php
// Simple diagnostic tool for troubleshooting PHP and server issues

// Basic information output
echo "<h2>PHP Server Information</h2>";

// Check PHP version
echo "<p>PHP Version: " . phpversion() . "</p>";

// Check if roundcube is correctly installed
echo "<h3>Roundcube Installation Check</h3>";
$roundcube_path = realpath(dirname(__FILE__));
echo "<p>Script location: $roundcube_path</p>";

// Check if required directories exist
echo "<h3>Directory Structure</h3>";
echo "<ul>";
foreach (['program', 'config', 'skins', 'plugins'] as $dir) {
    $path = $roundcube_path . '/' . $dir;
    $exists = is_dir($path);
    echo "<li>$dir directory: " . ($exists ? "Exists" : "Missing") . "</li>";
}
echo "</ul>";

// Check if config file exists
echo "<h3>Configuration Check</h3>";
$config_file = $roundcube_path . '/config/config.inc.php';
$config_exists = file_exists($config_file);
echo "<p>Config file: " . ($config_exists ? "Exists" : "Missing") . "</p>";

// Check file permissions
echo "<h3>File Permissions</h3>";
echo "<ul>";
echo "<li>Web root readable: " . (is_readable($roundcube_path) ? "Yes" : "No") . "</li>";
if ($config_exists) {
    echo "<li>Config file readable: " . (is_readable($config_file) ? "Yes" : "No") . "</li>";
}
echo "</ul>";

// Test database connection if config exists
echo "<h3>Database Connection Test</h3>";
if ($config_exists && is_readable($config_file)) {
    // Try to extract database connection string without loading the entire config
    $config_content = file_get_contents($config_file);
    preg_match("/\$config\['db_dsnw'\]\s*=\s*'([^']+)'/", $config_content, $matches);
    
    if (isset($matches[1])) {
        $dsn = $matches[1];
        echo "<p>Database DSN found: " . htmlspecialchars(preg_replace('/:[^:]*@/', ':***@', $dsn)) . "</p>";
        
        // Try to connect to the database
        try {
            if (strpos($dsn, 'mysql') === 0) {
                $parsed = parse_url(str_replace('mysql://', '', $dsn));
                $dbuser = $parsed['user'] ?? '';
                $dbpass = $parsed['pass'] ?? '';
                $dbhost = $parsed['host'] ?? 'localhost';
                $dbname = ltrim($parsed['path'] ?? '', '/');
                
                $mysqli = new mysqli($dbhost, $dbuser, $dbpass, $dbname);
                if ($mysqli->connect_errno) {
                    echo "<p>MySQL Connection Failed: " . $mysqli->connect_error . "</p>";
                } else {
                    echo "<p>MySQL Connection: Success</p>";
                    $mysqli->close();
                }
            } else {
                echo "<p>Non-MySQL database detected, skipping connection test</p>";
            }
        } catch (Exception $e) {
            echo "<p>Database Connection Error: " . $e->getMessage() . "</p>";
        }
    } else {
        echo "<p>Could not extract database connection string from config</p>";
    }
} else {
    echo "<p>Config file not available to test database connection</p>";
}

// Test mail server connectivity
echo "<h3>Mail Server Connectivity Tests</h3>";

// Function to test socket connection
function test_socket($host, $port, $timeout = 5) {
    $socket = @fsockopen($host, $port, $errno, $errstr, $timeout);
    if (!$socket) {
        return "Failed: $errstr ($errno)";
    } else {
        $response = fgets($socket, 1024);
        fclose($socket);
        return "Success: " . htmlspecialchars(trim($response));
    }
}

// Test IMAP connection
echo "<p>IMAP (143) connection: " . test_socket('localhost', 143) . "</p>";

// Test SMTP connection
echo "<p>SMTP (25) connection: " . test_socket('localhost', 25) . "</p>";

// Show loaded PHP modules
echo "<h3>Loaded PHP Modules</h3>";
$modules = get_loaded_extensions();
sort($modules);
echo "<p>" . implode(", ", $modules) . "</p>";

// Check for critical extensions needed by Roundcube
echo "<h3>Critical PHP Extensions</h3>";
$critical = ['pdo', 'pdo_mysql', 'json', 'mbstring', 'session', 'curl', 'xml'];
echo "<ul>";
foreach ($critical as $ext) {
    echo "<li>$ext: " . (extension_loaded($ext) ? "Loaded" : "Missing") . "</li>";
}
echo "</ul>";

// Server information
echo "<h3>Server Information</h3>";
echo "<p>Server Software: " . ($_SERVER['SERVER_SOFTWARE'] ?? 'Unknown') . "</p>";
echo "<p>Server Name: " . ($_SERVER['SERVER_NAME'] ?? 'Unknown') . "</p>";
echo "<p>Document Root: " . ($_SERVER['DOCUMENT_ROOT'] ?? 'Unknown') . "</p>";
echo "<p>PHP SAPI: " . php_sapi_name() . "</p>";

// Include phpinfo for detailed information
echo "<h3>Detailed PHP Information</h3>";
echo "<div style='height: 300px; overflow-y: scroll; border: 1px solid #ccc; padding: 10px;'>";
phpinfo();
echo "</div>";
?>