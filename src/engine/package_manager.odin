#+feature dynamic-literals

package engine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:c/libc"

// Package manager for VoidEngine
// Supports: void get <package>
// Packages are fetched from git repositories or local paths

Package_Source :: enum {
	GIT,
	LOCAL,
	REGISTRY,
}

Package_Info :: struct {
	name:         string,
	version:      string,
	source:       Package_Source,
	url:          string,
	installed:    bool,
	install_path: string,
}

Package_Registry :: struct {
	packages: map[string]Package_Info,
}

PACKAGES_DIR :: "void_packages"
REGISTRY_URL :: "https://github.com/voidengine/packages"

// Default package registry (built-in known packages)
default_registry := map[string]Package_Info{
	"math" = Package_Info{
		name    = "math",
		version = "0.1.0",
		source  = .GIT,
		url     = "https://github.com/voidengine/package-math",
	},
	"physics" = Package_Info{
		name    = "physics",
		version = "0.1.0",
		source  = .GIT,
		url     = "https://github.com/voidengine/package-physics",
	},
	"ui" = Package_Info{
		name    = "ui",
		version = "0.1.0",
		source  = .GIT,
		url     = "https://github.com/voidengine/package-ui",
	},
	"net" = Package_Info{
		name    = "net",
		version = "0.1.0",
		source  = .GIT,
		url     = "https://github.com/voidengine/package-net",
	},
}

// Initialize packages directory
package_manager_init :: proc() {
	if !os.exists(PACKAGES_DIR) {
		os.make_directory(PACKAGES_DIR)
		fmt.println("[PACKAGE] Created packages directory:", PACKAGES_DIR)
	}
}

// Fetch and install a package
package_manager_fetch :: proc(package_name: string) -> bool {
	package_manager_init()

	fmt.println("[PACKAGE] Resolving:", package_name)

	// Check if it's a direct Git URL
	if strings.contains(package_name, "://") || strings.contains(package_name, "@") {
		return fetch_from_git(package_name, package_name)
	}

	// Check if it's a local path
	if os.exists(package_name) && os.is_dir(package_name) {
		return install_local_package(package_name)
	}

	// Look up in default registry
	info, found := default_registry[package_name]
	if found {
		switch info.source {
		case .GIT:
			return fetch_from_git(info.url, info.name)
		case .LOCAL:
			return install_local_package(info.url)
		case .REGISTRY:
			return fetch_from_registry(info.name)
		}
	}

	// Try to construct GitHub URL from package name
	github_url := fmt.tprintf("https://github.com/voidengine/package-%s", package_name)
	fmt.println("[PACKAGE] Trying GitHub URL:", github_url)
	return fetch_from_git(github_url, package_name)
}

// Fetch package from Git repository
fetch_from_git :: proc(url: string, package_name: string) -> bool {
	install_path := fmt.tprintf("%s/%s", PACKAGES_DIR, package_name)

	// Check if already installed
	if os.exists(install_path) {
		fmt.println("[PACKAGE] Package already exists:", package_name)
		fmt.println("[PACKAGE] To update, remove", install_path, "and re-run void get")
		return true
	}

	fmt.println("[PACKAGE] Cloning from:", url)
	fmt.println("[PACKAGE] Install path:", install_path)

	// Use git clone to fetch the package
	cmd := fmt.tprintf("git clone --depth=1 %s %s", url, install_path)
	fmt.println("[PACKAGE] Running:", cmd)

	cmd_cstr := strings.clone_to_cstring(cmd)
	defer delete(cmd_cstr)

	err := libc.system(cmd_cstr)
	if err != 0 {
		fmt.println("[PACKAGE ERROR] Failed to clone repository")
		fmt.println("[PACKAGE] Make sure git is installed and the URL is accessible")
		return false
	}

	fmt.println("[PACKAGE] Successfully installed:", package_name)
	fmt.println("[PACKAGE] Location:", install_path)

	// Try to read package metadata
	read_package_metadata(install_path)

	return true
}

// Install package from local path
install_local_package :: proc(local_path: string) -> bool {
	package_name := filepath.base(local_path)
	install_path := fmt.tprintf("%s/%s", PACKAGES_DIR, package_name)

	if os.exists(install_path) {
		fmt.println("[PACKAGE] Package already exists:", package_name)
		return true
	}

	fmt.println("[PACKAGE] Installing from local path:", local_path)

	// For local paths, we can either copy or symlink
	// Using cp -r for simplicity
	when ODIN_OS == .Windows {
		cmd := fmt.tprintf("xcopy /E /I \"%s\" \"%s\"", local_path, install_path)
	} else {
		cmd := fmt.tprintf("cp -r \"%s\" \"%s\"", local_path, install_path)
	}

	cmd_cstr := strings.clone_to_cstring(cmd)
	defer delete(cmd_cstr)

	err := libc.system(cmd_cstr)
	if err != 0 {
		fmt.println("[PACKAGE ERROR] Failed to copy local package")
		return false
	}

	fmt.println("[PACKAGE] Successfully installed:", package_name)
	return true
}

// Fetch from package registry
fetch_from_registry :: proc(package_name: string) -> bool {
	fmt.println("[PACKAGE] Fetching from registry:", REGISTRY_URL)
	fmt.println("[PACKAGE] Package:", package_name)
	fmt.println("[PACKAGE] Registry support is coming soon!")
	fmt.println("[PACKAGE] For now, use: void get <git-url>")
	return false
}

// Read and display package metadata
read_package_metadata :: proc(install_path: string) {
	manifest_path := fmt.tprintf("%s/void.json", install_path)
	if !os.exists(manifest_path) {
		return
	}

	data, read_err := os.read_entire_file(manifest_path, context.allocator)
	if read_err != os.ERROR_NONE {
		return
	}
	defer delete(data)

	fmt.println("[PACKAGE] Manifest found:")
	fmt.println(string(data))
}

// List installed packages
package_manager_list :: proc() {
	package_manager_init()

	fmt.println("=== Installed Packages ===")

	if !os.exists(PACKAGES_DIR) {
		fmt.println("No packages installed")
		return
	}

	fd, err := os.open(PACKAGES_DIR)
	if err != os.ERROR_NONE {
		fmt.println("[PACKAGE ERROR] Cannot read packages directory")
		return
	}
	defer os.close(fd)

	fis, read_err := os.read_dir(fd, -1, context.allocator)
	if read_err != os.ERROR_NONE {
		fmt.println("[PACKAGE ERROR] Cannot list packages")
		return
	}
	defer delete(fis)

	if len(fis) == 0 {
		fmt.println("No packages installed")
		return
	}

	for fi in fis {
		if fi.type == .Directory {
			fmt.println("  -", fi.name)
		}
	}
}

// Remove an installed package
package_manager_remove :: proc(package_name: string) -> bool {
	install_path := fmt.tprintf("%s/%s", PACKAGES_DIR, package_name)

	if !os.exists(install_path) {
		fmt.println("[PACKAGE] Package not found:", package_name)
		return false
	}

	fmt.println("[PACKAGE] Removing:", package_name)

	// Remove directory
	when ODIN_OS == .Windows {
		cmd := fmt.tprintf("rmdir /S /Q \"%s\"", install_path)
	} else {
		cmd := fmt.tprintf("rm -rf \"%s\"", install_path)
	}

	cmd_cstr := strings.clone_to_cstring(cmd)
	defer delete(cmd_cstr)

	err := libc.system(cmd_cstr)
	if err != 0 {
		fmt.println("[PACKAGE ERROR] Failed to remove package")
		return false
	}

	fmt.println("[PACKAGE] Removed:", package_name)
	return true
}

// Show package manager help
package_manager_help :: proc() {
	fmt.println("=== VoidEngine Package Manager ===")
	fmt.println("")
	fmt.println("Usage: void get <package>")
	fmt.println("")
	fmt.println("Commands:")
	fmt.println("  void get <name>       Install a package by name")
	fmt.println("  void get <git-url>    Install from a Git repository")
	fmt.println("  void get <local-path>  Install from a local directory")
	fmt.println("")
	fmt.println("Known packages:")
	for name, info in default_registry {
		fmt.println("  -", name, "(", info.version, ")")
	}
	fmt.println("")
	fmt.println("Packages are installed to: ./", PACKAGES_DIR)
	fmt.println("Import in your game: import \"package:name\"")
}
