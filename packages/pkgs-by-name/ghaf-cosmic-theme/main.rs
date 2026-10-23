// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0
use cosmic_config::{Config, CosmicConfigEntry};
use cosmic_theme::{Theme, ThemeBuilder};

// Usage: ghaf-cosmic-theme <builder.ron> <theme-id> <out-dir>
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let builder: ThemeBuilder = ron::from_str(&std::fs::read_to_string(&args[1]).unwrap()).unwrap();
    let id = &args[2];
    let out = std::path::PathBuf::from(&args[3]);
    let config = |name: &str, version| Config::with_custom_path(name, version, out.clone()).unwrap();

    builder
        .clone()
        .build()
        .write_entry(&config(id, Theme::VERSION))
        .unwrap();
    builder
        .write_entry(&config(&format!("{id}.Builder"), ThemeBuilder::VERSION))
        .unwrap();
}
