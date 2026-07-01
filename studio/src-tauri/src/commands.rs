use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::{AppHandle, Manager};
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_shell::ShellExt;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectInfo {
    pub name: String,
    pub path: String,
    pub examples: Vec<String>,
    pub has_makefile: bool,
    pub has_tests: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommandOutput {
    pub stdout: String,
    pub stderr: String,
    pub success: bool,
    pub exit_code: Option<i32>,
}

pub struct StudioState {
    pub current_project: Mutex<Option<ProjectInfo>>,
}

impl Default for StudioState {
    fn default() -> Self {
        StudioState {
            current_project: Mutex::new(None),
        }
    }
}

impl StudioState {
    pub fn set_project(&self, project: ProjectInfo) {
        if let Ok(mut guard) = self.current_project.lock() {
            *guard = Some(project);
        }
    }
}

#[tauri::command]
pub async fn pick_project_folder(app: AppHandle) -> Result<Option<ProjectInfo>, String> {
    let folder = app
        .dialog()
        .file()
        .blocking_pick_folder()
        .ok_or("No folder selected")?;

    let path = folder.as_path().map(|p| p.to_path_buf()).unwrap_or_default();
    if path.as_os_str().is_empty() {
        return Ok(None);
    }
    if let Some(state) = app.try_state::<StudioState>() {
        if let Ok(project) = scan_project(path.clone()) {
            if let Some(ref p) = project {
                state.set_project(p.clone());
            }
            return Ok(project);
        }
    }
    scan_project(path)
}

#[tauri::command]
pub async fn load_project(path: String) -> Result<ProjectInfo, String> {
    scan_project(PathBuf::from(path))?.ok_or_else(|| "Not a valid VoidEngine project".to_string())
}

fn scan_project(path: PathBuf) -> Result<Option<ProjectInfo>, String> {
    if !path.is_dir() {
        return Ok(None);
    }

    let makefile = path.join("Makefile").exists();
    let tests_dir = path.join("tests").is_dir();
    let src_core = path.join("src/core").is_dir();
    let examples_dir = path.join("examples").is_dir();

    if !src_core || !examples_dir {
        if !makefile {
            return Ok(None);
        }
    }

    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_string();

    let examples = if examples_dir {
        std::fs::read_dir(path.join("examples"))
            .map_err(|e| e.to_string())?
            .filter_map(|entry| entry.ok())
            .filter(|entry| entry.path().is_dir())
            .filter_map(|entry| entry.file_name().into_string().ok())
            .collect::<Vec<_>>()
    } else {
        Vec::new()
    };

    Ok(Some(ProjectInfo {
        name,
        path: path.to_string_lossy().to_string(),
        examples,
        has_makefile: makefile,
        has_tests: tests_dir,
    }))
}

#[tauri::command]
pub async fn run_command(
    app: AppHandle,
    project_path: String,
    command: String,
) -> Result<CommandOutput, String> {
    let path = PathBuf::from(project_path);
    if !path.is_dir() {
        return Err("Project path does not exist".to_string());
    }

    let cmd = app
        .shell()
        .command("sh")
        .arg("-c")
        .arg(&command)
        .current_dir(&path);

    let output = cmd.output().await.map_err(|e| e.to_string())?;

    Ok(CommandOutput {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        success: output.status.success(),
        exit_code: output.status.code(),
    })
}

#[tauri::command]
pub fn discover_projects_in_parent(path: String) -> Result<Vec<ProjectInfo>, String> {
    let parent = PathBuf::from(path)
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."));

    let mut projects = Vec::new();
    if let Ok(entries) = std::fs::read_dir(&parent) {
        for entry in entries.flatten() {
            if let Ok(Some(project)) = scan_project(entry.path()) {
                projects.push(project);
            }
        }
    }

    Ok(projects)
}

#[tauri::command]
pub fn get_default_projects() -> Result<Vec<ProjectInfo>, String> {
    let default_paths = vec![PathBuf::from(
        "/home/synth/projects/active/voidengine",
    )];

    let mut projects = Vec::new();
    for path in default_paths {
        if let Ok(Some(project)) = scan_project(path) {
            projects.push(project);
        }
    }
    Ok(projects)
}
