use std::path::PathBuf;
use std::sync::LazyLock;

use crate::config_manager::{ConfigSchemaItem, ConfigValue, Limits};

pub const KEY_EMBEDDED_SCRIPT: &str = "embedded_script";
pub const KEY_NONE: &str = "none";

pub fn expand_home_path(path: &str) -> String {
    if path != "~" && !path.starts_with("~/") {
        return path.to_string();
    }

    let Some(home) = std::env::var_os("HOME") else {
        return path.to_string();
    };

    let mut expanded = PathBuf::from(home);
    if path != "~" {
        expanded.push(&path[2..]);
    }
    expanded.to_string_lossy().into_owned()
}

pub static CONFIG_SCHEMA: LazyLock<Vec<ConfigSchemaItem>> = LazyLock::new(|| {
    vec![
        ConfigSchemaItem {
            key: "path_to_iso".to_string(),
            default_value: ConfigValue::String("path-to-iso".to_string()),
            limits: None,
        },
        ConfigSchemaItem {
            key: "path_to_custom_iso".to_string(),
            default_value: ConfigValue::String(expand_home_path("~/.config/safe-stick/custom.iso")),
            limits: None,
        },
        ConfigSchemaItem {
            key: "work_dir".to_string(),
            default_value: ConfigValue::String(expand_home_path("~/.config/safe-stick/work")),
            limits: None,
        },
        ConfigSchemaItem {
            key: "customize_script".to_string(),
            default_value: ConfigValue::String(KEY_EMBEDDED_SCRIPT.to_string()),
            limits: None,
        },
        ConfigSchemaItem {
            key: "passwort_script".to_string(),
            default_value: ConfigValue::String(KEY_EMBEDDED_SCRIPT.to_string()),
            limits: None,
        },
        ConfigSchemaItem {
            key: "usb_device".to_string(),
            default_value: ConfigValue::String(KEY_NONE.to_string()),
            limits: None,
        },
        ConfigSchemaItem {
            key: "linux_size_gb".to_string(),
            default_value: ConfigValue::Integer(5),
            limits: Some(Limits {
                min: Some(1.0),
                max: Some(100.0),
            }),
        },
        ConfigSchemaItem {
            key: "encrypt_size_gb".to_string(),
            default_value: ConfigValue::Integer(1),
            limits: Some(Limits {
                min: Some(1.0),
                max: Some(100.0),
            }),
        },
        ConfigSchemaItem {
            key: "none_encrypt_size_gb".to_string(),
            default_value: ConfigValue::Integer(1),
            limits: Some(Limits {
                min: Some(1.0),
                max: Some(100.0),
            }),
        },
    ]
});

#[cfg(test)]
mod tests {
    use super::expand_home_path;

    #[test]
    fn expands_home_directory_prefix_only() {
        if let Some(home) = std::env::var_os("HOME") {
            let home = PathBuf::from(home);
            assert_eq!(
                expand_home_path("~/.config/safe-stick/work"),
                home.join(".config/safe-stick/work")
                    .to_string_lossy()
                    .into_owned()
            );
            assert_eq!(expand_home_path("relative/path"), "relative/path");
        }
    }

    use std::path::PathBuf;
}
