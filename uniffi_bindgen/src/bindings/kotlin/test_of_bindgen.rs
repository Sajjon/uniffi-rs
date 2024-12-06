use crate::{
    bindings::KotlinBindingGenerator, interface, BindingGenerator, Component, ComponentInterface,
    GenerationSettings,
};

use super::gen_kotlin;
use camino::Utf8PathBuf;
use gen_kotlin::{generate_bindings, Config};

fn config() -> Config {
    let config = Config::default();

    config
}

#[test]
fn test_kotlin_bindgen() {
    let config = config();
    let ci = ComponentInterface::new("Foobar");
    let bindgen = KotlinBindingGenerator;

    let settings = GenerationSettings {
        cdylib: None,
        out_dir: Utf8PathBuf::default(),
        try_format_code: false,
    };

    let mut components = vec![Component {
        ci,
        config: config.clone(),
    }];

    bindgen
        .update_component_configs(&settings, &mut components)
        .unwrap();

    let component = components.iter().next().unwrap();

    let kotlin = generate_bindings(&config, &component.ci).unwrap();
    let expected = r#"
    package uniffi.Foobar
    "#;
    assert_eq!(kotlin, expected)
}
