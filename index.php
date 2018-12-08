<?php

/*

This application routes requests for the kinvatjobs.com site. It is an 
example of basic routing for database driven website in php. First a database 
connection is established and the handle is stored in the $CRUD variable, which 
will also accumulate variables and information during the scripts life to be 
displayed after all the calculations are made.

The site is running on an aws instance running ubuntu 14.x, it connects to a 
MySQL database via Amazon RDS for the main datastore and manages the sessions 
using an instance of DynamoDb. File uploads are stored via S3 Bucket. The front
end is coded using Bootstrap and Async requests in native JavaScript.

The entire application integrates email sending services including cronjobs that 
send out reminders to users who have not completed the registration process.

The database is scalable in that form fields are able to be added without any 
coding, which makes things kind of complicated but gives the client the flexibility 
he needs.

*/


require 'vendor/autoload.php'; // load dependencies (e.g. aws sdk)
include_once "config/constants.inc"; // load constants into memory
include_once "config/config.inc"; // load other program stuff
include_once 'templates/templates.php'; // master template handler
include_once 'inc/includes.inc'; // includes directory files
include_once "redacted"; // load mysql credentials

ini_set('session.cache_limiter','public');
session_cache_limiter(false);

// composer require ramsey/uuid
if (DEPLOYMENT_BUILD == "DEBUG") {
    include_once 'inc/amazonTests.inc'; // testing functions
    ini_set("log_errors", 1);
    ini_set("error_log", "/Users/theHorse/Desktop/php-error.log");
}

init();

if(getSettingBool("displayFrontPage")){
    main();
}
else {
    siteIsDown();
}

// Handle main routing
function main()
{
    // query
    if (isset($_GET['q'])) {
        $q = $_GET['q'];
        handleRequest($q);
    }
    // asynchronous
    else if (isset($_GET['a'])) {
        $a = $_GET['a'];
        handleAsync($a);
    }
    // call to index
    else {
        $q = "";
        handleRequest($q);
    }
    exit();
}

function handleRequest($q)
{
    // if user just logged in display a relative menu
    // else forward the request to the anonymous user functions

    global $CRUD; // global database handle
    
    if (isset($_SESSION['user_id'])) {
        // get role for user from database.
        $role = roleForUserFromId($_SESSION['user_id']);
        error_log("Index.php Session:user_id" . $_SESSION['user_id'] . " role: " . $role, 0);
    } else $role = "";
    
    // section A: for contractors
    // section B: for administrators
    if ($q == "contractor" ||
        $q == "administrator") {
        
        // here we determine if the user has permission to access selected area.
        // contractors AND administers have to be logged in otherwise, register or login page.
        if (login_check($CRUD['mysql']) == true) {
        
            // this is where we determine that contractor or admin is or is not suspended
            if (roleIsAuthorized($_SESSION['user_id'])) {
            
                // new users must also authorize their accounts
                if (accountIsActivated($_SESSION['user_id'])) {

                    // now we determine what they want and if their role allows for that request
                    if ($role == "contractor") {
                        $message = $_SESSION['user_id'] . " logged in as " . upperCaseName($role);
                        contractorFunctions($_GET['p']);
                    } else if ($role == "administrator") {
                        $message = $_SESSION['user_id'] . " logged in as " . upperCaseName($role);
                        administrationFunctions($_GET['p']);
                    } else {
                        // should never get here.
                        error_log("Role " . $role . " Not recognized", 0);
                    }
                }
                else {
                    $error['class'] = "Activation Error";
                    $error['message'] = "User Account is not Activated. In order to use the application's functions, please activate your account.";
                    displayActivationError($error);
                    $message = $error['class'] . " " . $error['message'];
                    error_log($message, 0);
                    logErrorToAdminConsole($message);
                }
            } else {
                $error['class'] = "Authorization Error";
                $error['message'] = "User Account is not Authorized. In order to use the application's functions, please request your account to be authorized.";
                displayError($error);
                $message = $error['class'] . " " . $error['message'];
                error_log($message, 0);
                logErrorToAdminConsole($message);
            }
        }
        // error on bad login
        else {
            $error['class'] = "Login Error";
            $error['message'] = "Could Not Log in. Either Invalid Login Credentials were supplied or the previous Session Timed Out.";
            displayError($error);
            $message = $error['class'] . " " . $error['message'];
            error_log($message, 0);
            logErrorToAdminConsole($message);
        }
    }
    else {
        anonymousFunctions($q); // login or register
    }
}

function contractorFunctions( $p ){
    // processes that require a logged in status
    global $CRUD;
    switch($p) {
        // contractor processes
        case "main":
            displayRegistration(); // some function
            break;
        case "profileEditor" :
            profileEditor();
            break;
        case "profileView" :
            profileView();
            break;
        case "documentView" :
            displayDocuments();
            break;
        case "agreeToTerms" :
            agreeToTerms();
            break;
        default:    // default
            nothing();
    }
    return;
}
function administrationFunctions( $q ){
    // processes that require a logged in status
    global $CRUD;
    $task = "";
    if (isset($_GET['t'])){
        $task = $_GET['t'];
    }
    switch($q) {
        // admin processes
        case "contractorList":
             contractorList();
            break;
        case "contractorProfile":
            contractorProfile();
            break;
        case "kPoints":
            kPointsLedger();
            break;
        case "editContractor":
            editContractor();
            break;
        case "contractorSearch":
            contractorSearch();
            break;
        case "departments":
            departments();
            break;
        case "administration":
            administration();
            break;
        case "statistics":
            displayStats();
            break;
        case "email":
            sendEmails($task);
            break;
        default:    // default
            administrationMenu();
    }
    return;
}
function anonymousFunctions( $q )
{
    // processes that do not require a logged in status
    global $CRUD;
    switch($q) {
        case "forgotPassword":
            forgotPassword();
            break;
        case "sendLink":
            requestLostPasswordEmail();
            break;
        case "changePassword":
            changePasswordForm();
            break;
        // anonymous user processes
        case "about" :
            about();
            break;
        case "contact" :
            contact();
            break;
        case "privacy" :
            privacy();
            break;
        case "processLogin":
            processLogin(); // handle login
            break;
        case "processLogout":
            processLogout(); // handle logout
            displayFrontPage();
            break;
        case "register":
            registration(); // display registration form
            break;
        case "registration_form" :
            if (!(processNewUser())){ // loginFunctions.inc
                displayError($CRUD['error']);
            }
            else {
                // registration success page
                registrationSuccessful();
            }
            break;
        default:    // default to show main page
            displayFrontPage();
    }
    return;
}
function handleAsync($a)
{
    switch($a) {
        // anonymous user processes
        // security is handled within profileEditorAsync
        case "profileEditor" :
            profileEditorAsync($_GET['t']); // t is for task
            break;
        case "fileUpload" :
            fileUploadAsync($_GET['t']);
            break;
        default :
            break;
    }
}
function init( )
{
    global $CRUD;
    $warnings = array();
    // future implementation would have a facade in between here to allow switching of the underlying database host company
    $CRUD['mysql'] = initAwsRds();
    $CRUD['nosql'] = initAwsDynamoDb();
    $CRUD['files'] = initAwsS3Bucket();
    if (! isset($CRUD['mysql'])){
        $error = "The server encountered an error. " . "Unable to connect to MySQL database";
        displayError($error);
    }
    else {
        if (DEPLOYMENT_BUILD == "DEBUG") {
            array_push($warnings, "mysql initialized");
        }
    }
    if (! isset($CRUD['nosql'])){
        $error = "The server encountered an error. " . "Unable to connect to NoSQL database";
        displayError($error);
    }
    else {
        // initialize the session...
        startSession();
        // print any console warnings that happened before session_start
        if (DEPLOYMENT_BUILD == "DEBUG") {
            array_push($warnings, "session initialized");
        }
    }
    if (! isset($CRUD['files'])){
        $error = "The server encountered an error. " . "Unable to connect to File Upload database";
        displayError($error);
    }
    else {
        if (DEPLOYMENT_BUILD == "DEBUG") {
            array_push($warnings, "file uploads initialized");
        }
    }
    $CRUD['WARNINGS'] = $warnings;
    $CRUD['TITLE'] = HTML_TITLE;
}
