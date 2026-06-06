package main

import "core:fmt"
import "core:os"
import "engine"

main :: proc() {
	fmt.println("🎹 VoidEngine v1.0.0")
	fmt.println("Usage: void <command> [args]")

	if len(os.args) < 2 {
		print_help()
		return
	}

	cmd := os.args[1]

	switch cmd {
	case "run":
		if len(os.args) < 3 {
			fmt.println("Usage: void run <dir>")
			return
		}
		engine.run_project(os.args[2])

	case "new":
		if len(os.args) < 3 {
			fmt.println("Usage: void new <name>")
			return
		}
		engine.create_project(os.args[2])

	case "build":
		if len(os.args) < 3 {
			fmt.println("Usage: void build <dir>")
			return
		}
		engine.build_project(os.args[2])

	case "get":
		if len(os.args) < 3 {
			engine.package_manager_help()
			return
		}
		success := engine.get_package(os.args[2])
		if !success {
			os.exit(1)
		}

	case "update":
		if len(os.args) < 3 {
			fmt.println("Usage: void update <package>")
			fmt.println("       void update-all")
			return
		}
		if os.args[2] == "-all" || os.args[2] == "--all" {
			engine.package_manager_update_all()
		} else {
			success := engine.package_manager_update(os.args[2])
			if !success {
				os.exit(1)
			}
		}

	case "packages":
		engine.package_manager_list()

	case "help", "--help", "-h":
		print_help()

	case:
		fmt.println("Unknown command:", cmd)
		print_help()
		os.exit(1)
	}
}

print_help :: proc() {
	fmt.println("\nCommands:")
	fmt.println("  run <dir>      Run a game project (with hot-reload)")
	fmt.println("  new <name>    Create a new game project")
	fmt.println("  build <dir>   Build standalone executable")
	fmt.println("  get <pkg>     Install a package")
	fmt.println("  packages      List installed packages")
	fmt.println("  help          Show this help message")
	fmt.println("\nOptions:")
	fmt.println("  --help, -h    Show help")
}
