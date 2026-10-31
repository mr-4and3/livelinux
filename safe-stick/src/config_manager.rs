use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

/// Unterstützte Datentypen für die Konfigurationswerte
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum ConfigValue {
    Integer(i64),
    Float(f64),
    String(String),
    Boolean(bool),
}

/// Optionale Grenzwerte für numerische Werte
#[derive(Debug, Clone)]
pub struct Limits {
    pub min: Option<f64>,
    pub max: Option<f64>,
}

/// Die Definition eines einzelnen Konfigurationseintrags (Schema)
#[derive(Debug, Clone)]
pub struct ConfigSchemaItem {
    pub key: String,
    pub default_value: ConfigValue,
    pub limits: Option<Limits>,
}

pub struct ConfigManager {
    file_path: PathBuf,
    schema: HashMap<String, ConfigSchemaItem>,
    pub current_config: HashMap<String, ConfigValue>,
}

impl ConfigManager {
    /// Erstellt einen neuen Manager, lädt die Datei oder erstellt sie mit Defaults,
    /// falls sie fehlt oder fehlerhaft ist.
    pub fn init<P: AsRef<Path>>(file_path: P, schema_list: Vec<ConfigSchemaItem>) -> Self {
        let mut schema = HashMap::new();
        let mut default_config = HashMap::new();

        for item in schema_list {
            default_config.insert(item.key.clone(), item.default_value.clone());
            schema.insert(item.key.clone(), item);
        }

        let path = file_path.as_ref().to_path_buf();
        let mut manager = ConfigManager {
            file_path: path,
            schema,
            current_config: HashMap::new(),
        };

        if !manager.file_path.exists() {
            // Datei existiert nicht -> mit Defaults erstellen
            manager.current_config = default_config;
            manager
                .save()
                .expect("Fehler beim Erstellen der Konfigurationsdatei");
        } else {
            // Datei existiert -> laden und validieren
            manager.load_and_validate(&default_config);
        }

        manager
    }

    /// Lädt die Datei und validiert sie gegen das Schema
    fn load_and_validate(&mut self, default_config: &HashMap<String, ConfigValue>) {
        let mut file = File::open(&self.file_path).expect("Datei konnte nicht geöffnet werden");
        let mut contents = String::new();
        file.read_to_string(&mut contents).unwrap_or(0);

        // Versuche zu parsen. Wenn die Datei komplett korrupt ist, nutzen wir leere Map (wird komplett überschrieben)
        let file_config: HashMap<String, ConfigValue> =
            serde_json::from_str(&contents).unwrap_or_default();
        let mut validated_config = HashMap::new();

        // Prüfe alle Schema-Vorgaben
        for (key, schema_item) in &self.schema {
            if let Some(file_val) = file_config.get(key) {
                if self.is_valid(file_val, schema_item) {
                    validated_config.insert(key.clone(), file_val.clone());
                    continue;
                }
            }
            // Falls Wert fehlt, falschen Typ hat oder Limits reißt -> Default nutzen
            validated_config.insert(key.clone(), schema_item.default_value.clone());
        }

        self.current_config = validated_config;

        // Falls ungültige Werte/unbekannte Keys verworfen wurden, Datei direkt bereinigen
        if self.current_config.len() != file_config.len()
            || file_config
                .iter()
                .any(|(k, _)| !self.schema.contains_key(k))
        {
            let _ = self.save();
        }
    }

    /// Prüft Typen und numerische Limits
    fn is_valid(&self, val: &ConfigValue, schema: &ConfigSchemaItem) -> bool {
        match (&schema.default_value, val) {
            (ConfigValue::Integer(_), ConfigValue::Integer(v)) => {
                self.check_limits(*v as f64, &schema.limits)
            }
            (ConfigValue::Float(_), ConfigValue::Float(v)) => self.check_limits(*v, &schema.limits),
            (ConfigValue::String(_), ConfigValue::String(_)) => true,
            (ConfigValue::Boolean(_), ConfigValue::Boolean(_)) => true,
            _ => false, // Typ-Mismatch
        }
    }

    fn check_limits(&self, val: f64, limits: &Option<Limits>) -> bool {
        if let Some(lim) = limits {
            if let Some(min) = lim.min {
                if val < min {
                    return false;
                }
            }
            if let Some(max) = lim.max {
                if val > max {
                    return false;
                }
            }
        }
        true
    }

    /// Speichert die aktuellen Programmdaten zurück in die Datei (inkl. Validierung)
    pub fn save(&mut self) -> std::io::Result<()> {
        let mut to_save = HashMap::new();

        // Stelle sicher, dass nur Schema-konforme Werte gespeichert werden
        for (key, schema_item) in &self.schema {
            let val = self
                .current_config
                .get(key)
                .unwrap_or(&schema_item.default_value);
            if self.is_valid(val, schema_item) {
                to_save.insert(key.clone(), val.clone());
            } else {
                to_save.insert(key.clone(), schema_item.default_value.clone());
            }
        }

        // Aktualisiere den State, falls vor dem Speichern ungültige Werte gesetzt wurden
        self.current_config = to_save.clone();

        let json_string = serde_json::to_string_pretty(&to_save)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;

        let mut file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(&self.file_path)?;

        file.write_all(json_string.as_bytes())?;
        Ok(())
    }

    /// Resets the configuration to the schema defaults and saves them.
    pub fn reset_to_defaults(&mut self) -> std::io::Result<()> {
        self.current_config = self
            .schema
            .iter()
            .map(|(key, item)| (key.clone(), item.default_value.clone()))
            .collect();
        self.save()
    }

    /// Hilfsfunktion zum Setzen eines Wertes im Programm
    pub fn set(&mut self, key: &str, value: ConfigValue) {
        self.current_config.insert(key.to_string(), value);
    }

    /// Hilfsfunktion zum Holen eines Wertes
    pub fn get(&self, key: &str) -> Option<&ConfigValue> {
        self.current_config.get(key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reset_to_defaults_updates_memory_and_saved_file() {
        let file_path = std::env::temp_dir().join(format!(
            "safe-stick-config-reset-{}-{}.json",
            std::process::id(),
            std::thread::current().name().unwrap_or("test")
        ));
        let _ = std::fs::remove_file(&file_path);
        let mut config = ConfigManager::init(&file_path, crate::config::CONFIG_SCHEMA.to_vec());

        config.set("path_to_iso", ConfigValue::String("custom.iso".to_string()));
        config
            .reset_to_defaults()
            .expect("reset and save default configuration");

        let saved: HashMap<String, ConfigValue> =
            serde_json::from_slice(&std::fs::read(&file_path).expect("read saved config"))
                .expect("parse saved config");
        for item in crate::config::CONFIG_SCHEMA.iter() {
            assert_eq!(config.get(&item.key), Some(&item.default_value));
            assert_eq!(saved.get(&item.key), Some(&item.default_value));
        }

        std::fs::remove_file(file_path).expect("remove temporary config file");
    }
}
