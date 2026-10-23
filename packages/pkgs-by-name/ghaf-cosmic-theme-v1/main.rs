// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0
use cosmic_config::{Config, CosmicConfigEntry};
use cosmic_theme::{Theme, ThemeBuilder};

// The v1 schema has colours as structs, not hex strings, and no frosted keys.
fn to_v1(ron: &str) -> String {
    let mut out = String::new();
    let mut rest = ron;
    while let Some(i) = rest.find("\"#") {
        let hex = &rest[i + 2..i + 10];
        let c = |j: usize| f32::from(u8::from_str_radix(&hex[j..j + 2], 16).unwrap()) / 255.0;
        out.push_str(&rest[..i]);
        out.push_str(&format!("(red: {}, green: {}, blue: {}, alpha: {})", c(0), c(2), c(4), c(6)));
        rest = &rest[i + 11..];
    }
    out.push_str(rest);
    out.replacen("\n(\n", "\n(\n    is_frosted: false,\n", 1)
}

// Usage: ghaf-cosmic-theme-v1 <builder.ron> <theme-id> <out-dir>
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let builder: ThemeBuilder = ron::from_str(&to_v1(&std::fs::read_to_string(&args[1]).unwrap())).unwrap();
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
