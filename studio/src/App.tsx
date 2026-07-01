// Tauri v2 API
import { invoke } from "@tauri-apps/api/core";
import { useEffect, useState } from "react";
import "./App.css";

interface ProjectInfo {
  name: string;
  path: string;
  examples: string[];
  has_makefile: boolean;
  has_tests: boolean;
}

interface CommandOutput {
  stdout: string;
  stderr: string;
  success: boolean;
  exit_code: number | null;
}

function App() {
  const [projects, setProjects] = useState<ProjectInfo[]>([]);
  const [selectedProject, setSelectedProject] = useState<ProjectInfo | null>(null);
  const [selectedExample, setSelectedExample] = useState<string>("");
  const [output, setOutput] = useState<string>("");
  const [running, setRunning] = useState<boolean>(false);

  useEffect(() => {
    loadDefaultProjects();
  }, []);

  const loadDefaultProjects = async () => {
    try {
      const found = await invoke<ProjectInfo[]>("get_default_projects");
      setProjects(found);
      if (found.length > 0) {
        selectProject(found[0]);
      }
    } catch (err) {
      log(`Failed to load default projects: ${err}`);
    }
  };

  const pickFolder = async () => {
    try {
      const folder = await invoke<ProjectInfo | null>("pick_project_folder");
      if (folder) {
        setProjects((prev) => {
          const filtered = prev.filter((p) => p.path !== folder.path);
          return [...filtered, folder];
        });
        selectProject(folder);
      }
    } catch (err) {
      log(`Failed to pick folder: ${err}`);
    }
  };

  const selectProject = (project: ProjectInfo) => {
    setSelectedProject(project);
    setSelectedExample(project.examples.length > 0 ? project.examples[0] : "");
    setOutput(`Selected project: ${project.name}\nPath: ${project.path}\nExamples: ${project.examples.join(", ") || "none"}`);
  };

  const run = async (command: string) => {
    if (!selectedProject) return;
    setRunning(true);
    log(`\n$ ${command}\n`);
    try {
      const result = await invoke<CommandOutput>("run_command", {
        projectPath: selectedProject.path,
        command,
      });
      if (result.stdout) log(result.stdout);
      if (result.stderr) log(result.stderr);
      log(`\nExit code: ${result.exit_code ?? "unknown"}`);
      log(result.success ? "✅ SUCCESS" : "❌ FAILED");
    } catch (err) {
      log(`Error running command: ${err}`);
    } finally {
      setRunning(false);
    }
  };

  const build = () => run("make build");
  const check = () => run("make check");
  const test = () => run("make test");
  const clean = () => run("make clean");
  const runGame = () => {
    if (!selectedExample) return;
    run(`./${selectedExample}`);
  };
  const buildExample = () => {
    if (!selectedExample) return;
    run(`make ${selectedExample}`);
  };

  const log = (text: string) => {
    setOutput((prev) => (prev ? prev + "\n" + text : text));
  };

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="sidebar-header">
          <h1>🎮 VoidEngine Studio</h1>
          <button onClick={pickFolder} disabled={running}>
            + Add Project
          </button>
        </div>

        <div className="projects">
          <h2>Projects</h2>
          {projects.length === 0 && (
            <p className="empty">No projects found. Add one to get started.</p>
          )}
          {projects.map((project) => (
            <button
              key={project.path}
              className={`project-item ${selectedProject?.path === project.path ? "active" : ""}`}
              onClick={() => selectProject(project)}
            >
              <span className="project-name">{project.name}</span>
              <span className="project-meta">{project.examples.length} examples</span>
            </button>
          ))}
        </div>

        <div className="project-details">
          <h2>Project Info</h2>
          {selectedProject ? (
            <>
              <p><strong>Name:</strong> {selectedProject.name}</p>
              <p><strong>Path:</strong> {selectedProject.path}</p>
              <p><strong>Makefile:</strong> {selectedProject.has_makefile ? "✅" : "❌"}</p>
              <p><strong>Tests:</strong> {selectedProject.has_tests ? "✅" : "❌"}</p>
            </>
          ) : (
            <p className="empty">Select a project</p>
          )}
        </div>
      </aside>

      <main className="main">
        <div className="toolbar">
          <button onClick={check} disabled={running || !selectedProject}>
            Check
          </button>
          <button onClick={test} disabled={running || !selectedProject?.has_tests}>
            Test
          </button>
          <button onClick={build} disabled={running || !selectedProject}>
            Build All
          </button>
          <button onClick={clean} disabled={running || !selectedProject}>
            Clean
          </button>
          <div className="divider" />
          {selectedProject?.examples.length ? (
            <>
              <select
                value={selectedExample}
                onChange={(e) => setSelectedExample(e.target.value)}
                disabled={running}
              >
                {selectedProject.examples.map((ex) => (
                  <option key={ex} value={ex}>
                    {ex}
                  </option>
                ))}
              </select>
              <button onClick={buildExample} disabled={running || !selectedExample}>
                Build Example
              </button>
              <button onClick={runGame} disabled={running || !selectedExample}>
                Run Example
              </button>
            </>
          ) : null}
        </div>

        <div className="output">
          <pre>{output}</pre>
        </div>
      </main>
    </div>
  );
}

export default App;
