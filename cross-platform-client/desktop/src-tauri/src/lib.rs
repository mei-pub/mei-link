use serde::Deserialize;
use std::sync::Mutex;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, PhysicalPosition, WebviewWindowBuilder, WindowEvent,
};
use tauri_plugin_shell::process::CommandChild;
use tauri_plugin_shell::ShellExt;

/// Holds the sidecar child process so we can kill it on exit.
struct SidecarState(Mutex<Option<CommandChild>>);

/// Holds a reference to the tray icon so we can update it at runtime.
struct TrayIconState(Mutex<Option<TrayIcon>>);

/// Holds the discovered API base URL (e.g. "http://127.0.0.1:51234").
struct ApiUrl(Mutex<String>);

/// Window definitions: label -> (title, width, height, resizable).
/// The popover window is pre-defined in tauri.conf.json; other windows are
/// created on demand to keep the startup lightweight.
const WINDOW_SPECS: &[(&str, &str, f64, f64, bool)] = &[
    ("main", "Meilink", 1060.0, 820.0, true),
	("settings", "设置", 760.0, 640.0, true),
    ("setup", "首次配置", 560.0, 640.0, false),
    ("tunnel-edit", "隧道", 660.0, 440.0, true),
    ("logs", "日志", 820.0, 620.0, true),
];

#[derive(Deserialize)]
struct DesktopSettings {
    #[serde(rename = "menuBarIconStyle")]
    menu_bar_icon_style: Option<String>,
}

#[tauri::command]
fn open_window(app: AppHandle, name: String) {
    if let Some((label, title, w, h, resizable)) =
        WINDOW_SPECS.iter().find(|(l, _, _, _, _)| *l == name)
    {
        // Singleton: if it exists, just focus it.
        if let Some(win) = app.get_webview_window(label) {
            let _ = win.show();
            let _ = win.set_focus();
            return;
        }
        let url = format!("{}.html", label);
        let mut builder =
            WebviewWindowBuilder::new(&app, *label, tauri::WebviewUrl::App(url.into()))
                .title(*title)
                .inner_size(*w, *h)
                .min_inner_size(w * 0.85, h * 0.85)
                .visible(true);
        if !*resizable {
            builder = builder.resizable(false);
        }
        let _ = builder.build();
    }
}

/// Returns the sidecar API base URL so the frontend can fetch from it.
#[tauri::command]
fn get_api_url(state: tauri::State<ApiUrl>) -> String {
    state.0.lock().unwrap().clone()
}

/// Quit the entire app: stop frpc via sidecar, kill sidecar, then exit.
#[tauri::command]
fn quit_app(app: AppHandle, state: tauri::State<SidecarState>) {
    // Best-effort: tell frpc to stop before killing the sidecar.
    if let Some(url_state) = app.try_state::<ApiUrl>() {
        let url = url_state.0.lock().unwrap().clone();
        if !url.is_empty() {
            // Stop frpc via API
            let _ = reqwest::blocking::Client::new()
                .post(format!("{}/api/control/stop", url))
                .send();
        }
    }
    // Kill the sidecar child.
    if let Some(child) = state.0.lock().unwrap().take() {
        let _ = child.kill();
    }
    app.exit(0);
}

/// Update the tray icon style. Called from the frontend settings page.
/// style values mirror Swift MenuBarIconStyle raw values.
#[tauri::command]
fn set_tray_icon_style(app: AppHandle, style: String) {
    let icon =
        tray_icon_bytes_for_style(&style).unwrap_or(include_bytes!("../icons/tray-portal.png"));
    if let Ok(img) = tauri::image::Image::from_bytes(icon) {
        if let Some(tray) = app.try_state::<TrayIconState>() {
            if let Some(tray) = tray.0.lock().unwrap().as_ref() {
                let _ = tray.set_icon(Some(img));
                let _ = tray.set_icon_as_template(true);
            }
        }
    }
}

fn tray_icon_bytes_for_style(style: &str) -> Option<&'static [u8]> {
    match style {
        "portal" => Some(include_bytes!("../icons/tray-portal.png")),
        "topology" => Some(include_bytes!("../icons/tray-topology.png")),
        "arrowRing" | "arrow-ring" => Some(include_bytes!("../icons/tray-arrow-ring.png")),
        "waveform" => Some(include_bytes!("../icons/tray-waveform.png")),
        "relay" => Some(include_bytes!("../icons/tray-relay.png")),
        _ => None,
    }
}

fn data_dir_for_home(home: &std::path::Path) -> std::path::PathBuf {
    // On macOS, use the same Application Support directory as the native Swift
    // app so configs and the sidecar port file are shared.
    #[cfg(target_os = "macos")]
    {
        home.join("Library")
            .join("Application Support")
            .join("Meilink")
    }
    #[cfg(not(target_os = "macos"))]
    {
        home.join(".meilink")
    }
}

fn data_dir() -> std::path::PathBuf {
    let home = dirs::home_dir().unwrap_or_else(|| std::path::PathBuf::from("."));
    data_dir_for_home(&home)
}

fn saved_menu_bar_icon_style() -> String {
    let settings_path = data_dir().join("settings.json");
    std::fs::read_to_string(settings_path)
        .ok()
        .and_then(|raw| serde_json::from_str::<DesktopSettings>(&raw).ok())
        .and_then(|settings| settings.menu_bar_icon_style)
        .unwrap_or_else(|| "portal".into())
}

fn popover_position_from_tray_rect(
    tray_x: f64,
    tray_y: f64,
    tray_width: f64,
    tray_height: f64,
    popover_width: f64,
) -> PhysicalPosition<i32> {
    PhysicalPosition::new(
        (tray_x + (tray_width / 2.0) - (popover_width / 2.0)).round() as i32,
        (tray_y + tray_height + 8.0).round() as i32,
    )
}

/// Polls the sidecar port file until it appears, then stores the API URL and
/// notifies all windows.
fn wait_for_sidecar(app: AppHandle) {
    let port_file = data_dir().join("sidecar.port");
    let app2 = app.clone();
    std::thread::spawn(move || {
        let url_state = app2.state::<ApiUrl>();
        for _ in 0..60 {
            if let Ok(content) = std::fs::read_to_string(&port_file) {
                let port: u16 = content.trim().parse().unwrap_or(0);
                if port > 0 {
                    let url = format!("http://127.0.0.1:{}", port);
                    // Verify the server is actually up by reading the port file
                    // (the sidecar writes it after the HTTP server starts).
                    *url_state.0.lock().unwrap() = url.clone();
                    let _ = app2.emit("sidecar-ready", &url);
                    return;
                }
            }
            std::thread::sleep(std::time::Duration::from_millis(500));
        }
        eprintln!("sidecar did not become ready within 30s");
    });
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_positioner::init())
        .plugin(tauri_plugin_shell::init())
        .manage(SidecarState(Mutex::new(None)))
        .manage(ApiUrl(Mutex::new(String::new())))
        .manage(TrayIconState(Mutex::new(None)))
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            // --- Start the Go sidecar ---
            let _ = std::fs::remove_file(data_dir().join("sidecar.port"));
            let (_rx, child) = app.shell().sidecar("meilink")?.args(["serve"]).spawn()?;
            app.state::<SidecarState>().0.lock().unwrap().replace(child);
            wait_for_sidecar(app.handle().clone());

            // --- System tray ---
            let show_main = MenuItem::with_id(app, "show-main", "打开主窗口", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "退出 Meilink", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_main, &quit_item])?;

            // Load a dedicated template icon for the tray (monochrome link icon).
            // Use include_bytes! to embed the icon at compile time so it works
            // regardless of CWD inside the .app bundle.
            let initial_style = saved_menu_bar_icon_style();
            let initial_icon = tray_icon_bytes_for_style(&initial_style)
                .unwrap_or(include_bytes!("../icons/tray-portal.png"));
            let tray_icon = tauri::image::Image::from_bytes(initial_icon)
                .unwrap_or_else(|_| app.default_window_icon().unwrap().clone());

            let _tray = TrayIconBuilder::with_id("main-tray")
                .icon(tray_icon)
                .icon_as_template(true)
                .tooltip("Meilink")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show-main" => {
                        open_window(app.clone(), "main".into());
                    }
                    "quit" => {
                        quit_app(app.clone(), app.state::<SidecarState>());
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        rect,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(popover) = app.get_webview_window("popover") {
                            if popover.is_visible().unwrap_or(false) {
                                let _ = popover.hide();
                            } else {
                                #[cfg(target_os = "macos")]
                                {
                                    let scale = popover.scale_factor().unwrap_or(1.0);
                                    let tray_pos = rect.position.to_physical::<f64>(scale);
                                    let tray_size = rect.size.to_physical::<f64>(scale);
                                    let popover_width = popover
                                        .outer_size()
                                        .map(|size| size.width as f64)
                                        .unwrap_or(330.0 * scale);
                                    let pos = popover_position_from_tray_rect(
                                        tray_pos.x,
                                        tray_pos.y,
                                        tray_size.width,
                                        tray_size.height,
                                        popover_width,
                                    );
                                    let _ = popover.set_position(pos);
                                }
                                #[cfg(not(target_os = "macos"))]
                                {
                                    use tauri_plugin_positioner::{Position, WindowExt};
                                    let _ =
                                        popover.move_window_constrained(Position::TrayBottomCenter);
                                }
                                let _ = popover.show();
                                let _ = popover.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            // Store the tray icon reference for runtime updates.
            if let Some(tray) = app.tray_by_id("main-tray") {
                app.state::<TrayIconState>()
                    .0
                    .lock()
                    .unwrap()
                    .replace(tray.clone());
            }

            // --- Show the main window on startup (after 300ms, like the native app) ---
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                std::thread::sleep(std::time::Duration::from_millis(300));
                open_window(handle, "main".into());
            });

            Ok(())
        })
        .on_window_event(|window, event| {
            // Close popover when it loses focus.
            if window.label() == "popover" {
                if let WindowEvent::Focused(false) = event {
                    let _ = window.hide();
                }
            }
            // Intercept close for all windows except popover: hide instead of close,
            // so the app stays alive (matches the native "close window != quit app").
            if let WindowEvent::CloseRequested { api, .. } = event {
                if window.label() != "popover" {
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            open_window,
            get_api_url,
            quit_app,
            set_tray_icon_style
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(target_os = "macos")]
    #[test]
    fn macos_data_dir_matches_native_app_support() {
        let home = std::path::PathBuf::from("/Users/example");
        assert_eq!(
            data_dir_for_home(&home),
            std::path::PathBuf::from("/Users/example/Library/Application Support/Meilink")
        );
    }

    #[test]
    fn popover_is_horizontally_centered_on_tray_rect() {
        let pos = popover_position_from_tray_rect(100.0, 0.0, 24.0, 22.0, 330.0);
        assert_eq!(pos.x, -53);
        assert_eq!(pos.y, 30);
    }

    #[test]
    fn dynamic_window_specs_match_swift_app_window_controller() {
        assert_eq!(
            WINDOW_SPECS,
            &[
                ("main", "Meilink", 1060.0, 820.0, true),
				("settings", "设置", 760.0, 640.0, true),
                ("setup", "首次配置", 560.0, 640.0, false),
                ("tunnel-edit", "隧道", 660.0, 440.0, true),
                ("logs", "日志", 820.0, 620.0, true),
            ]
        );
    }

    #[test]
    fn tauri_config_window_sizes_match_swift_app_window_controller() {
        let config_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tauri.conf.json");
        let raw = std::fs::read_to_string(config_path).expect("read tauri.conf.json");
        let config: serde_json::Value = serde_json::from_str(&raw).expect("parse tauri.conf.json");
        let windows = config["app"]["windows"]
            .as_array()
            .expect("app.windows should be an array");

        let size_for = |label: &str| -> (u64, u64) {
            let window = windows
                .iter()
                .find(|window| window["label"] == label)
                .unwrap_or_else(|| panic!("missing window label {label}"));
            (
                window["width"].as_u64().expect("window width"),
                window["height"].as_u64().expect("window height"),
            )
        };

        assert_eq!(size_for("popover"), (330, 440));
        assert_eq!(size_for("main"), (1060, 820));
		assert_eq!(size_for("settings"), (760, 640));
        assert_eq!(size_for("setup"), (560, 640));
        assert_eq!(size_for("tunnel-edit"), (660, 440));
        assert_eq!(size_for("logs"), (820, 620));
    }

    #[test]
    fn swift_menu_icon_values_map_to_tray_assets() {
        assert!(tray_icon_bytes_for_style("portal").is_some());
        assert!(tray_icon_bytes_for_style("topology").is_some());
        assert!(tray_icon_bytes_for_style("arrowRing").is_some());
        assert!(tray_icon_bytes_for_style("arrow-ring").is_some());
        assert!(tray_icon_bytes_for_style("waveform").is_some());
        assert!(tray_icon_bytes_for_style("relay").is_some());
    }
}
