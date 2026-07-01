#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            Ok(())
        })
        .manage(commands::StudioState::default())
        .invoke_handler(tauri::generate_handler![
            commands::pick_project_folder,
            commands::load_project,
            commands::run_command,
            commands::discover_projects_in_parent,
            commands::get_default_projects,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

mod commands;
