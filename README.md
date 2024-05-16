
# Automated BookStack Installation Scripts

This repository contains Bash scripts for automating the installation of BookStack on various systems.

## Scripts

### BookStack Installation

-   **Script Name**: `installation-almalinux-9.sh`

-   **Description**: This script automates the installation of [BookStack](https://www.bookstackapp.com/), a platform designed for organizing and storing documentation and knowledge base articles.

-   **Features**:
    -   Automated installation process, including package installation, database configuration, and Nginx setup.
    -   Secure configuration with SELinux disabled and firewall settings configured.
    -   Support for HTTPS with optional Nginx configuration.
    -   Database setup with randomized passwords for enhanced security.
    -   PHP-FPM configuration for optimized performance and resource usage.
    -   Colored output for clear feedback during installation, with summary exit messages.


## Usage (AlmaLinux 9)

1.  Clone this repository to your AlmaLinux system:

    ```bash
    git clone https://github.com/username/automated-installations.git
    ```
    
2.  Navigate to the cloned directory:
    
    ```bash
    cd automated-installations
    ```
    
3.  Make the desired script executable:
    
    ```bash
    chmod +x installation-almalinux-9.sh
    ```
    
4.  Execute the script **root**/sudo:
    
    ```bash
    ./installation-almalinux-9.sh
    ```
    
5.  Follow the on-screen prompts and provide necessary information when prompted.
    

## Configuration

-   **HTTPS Configuration**: By default, HTTPS support is enabled in the script. You can disabled it by setting the `CONFIGURE_NGINX_AS_HTTPS` variable to `false`.